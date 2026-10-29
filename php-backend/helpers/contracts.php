<?php
/**
 * Employee contracts: validation, the company's alarm settings and the daily expiry check.
 * The check runs lazily when an HR user's app asks for its notifications (no cron job needed), at most once a day per company.
 */

const CONTRACT_TYPES = ['permanent', 'fixed_term', 'probation', 'part_time', 'temporary', 'internship'];

function contract_valid_date($v): ?string {
    if ($v === null || $v === '') return null;
    $d = DateTime::createFromFormat('Y-m-d', (string)$v);
    if (!$d || $d->format('Y-m-d') !== (string)$v) error_response('Contract dates must be YYYY-MM-DD', 422);
    return $d->format('Y-m-d');
}

/**
 * Read the contract fields from a request body. Only the keys that are present are returned (column => value), so a plain
 * profile edit never wipes a contract. `$current` is the stored employee row, used to complete and check partial updates.
 */
function contract_fields(array $body, ?array $current = null): array {
    $keys = ['contract_type', 'contract_start', 'contract_end', 'contract_months'];
    if (!array_intersect($keys, array_keys($body))) return [];
    $get = fn(string $k) => array_key_exists($k, $body) ? ($body[$k] === '' ? null : $body[$k]) : ($current[$k] ?? null);

    $type = $get('contract_type');
    if ($type !== null && !in_array($type, CONTRACT_TYPES, true)) error_response('Unknown contract type', 422);
    $start  = contract_valid_date($get('contract_start'));
    $end    = contract_valid_date($get('contract_end'));
    $months = $get('contract_months');
    $months = ($months === null) ? null : max(1, min(240, (int)$months));

    if ($type === 'permanent') { $end = null; $months = null; }
    elseif ($end === null && $start !== null && $months !== null) {
        $end = (new DateTime($start))->modify("+$months months -1 day")->format('Y-m-d');
    }
    if ($start !== null && $end !== null && $end < $start) error_response('The contract cannot end before it starts', 422);
    return ['contract_type' => $type, 'contract_start' => $start, 'contract_end' => $end, 'contract_months' => $months];
}

function contracts_settings(PDO $pdo): array {
    $s = $pdo->prepare("SELECT * FROM contract_settings WHERE company_id = ?");
    $s->execute([cid()]);
    $r = $s->fetch();
    return $r ?: ['company_id' => cid(), 'remind_days' => '30,14,7,1', 'notify_hr' => 1, 'notify_manager' => 1, 'notify_employee' => 0, 'email_hr' => 0, 'remind_expired' => 1, 'last_run' => null];
}

function contracts_days(string $csv): array {
    $d = array_values(array_unique(array_filter(array_map('intval', explode(',', $csv)), fn($n) => $n >= 0 && $n <= 365)));
    rsort($d);
    return $d;
}

/** The settings the way the apps read them (days as a list, switches as true/false). */
function contracts_public(PDO $pdo): array {
    $s = contracts_settings($pdo);
    return [
        'remind_days' => contracts_days((string)$s['remind_days']),
        'notify_hr' => !empty($s['notify_hr']), 'notify_manager' => !empty($s['notify_manager']), 'notify_employee' => !empty($s['notify_employee']),
        'email_hr' => !empty($s['email_hr']), 'remind_expired' => !empty($s['remind_expired']),
    ];
}

/** Make the next notification poll re-check the contracts (after a setting or a contract changed). */
function contracts_reset(PDO $pdo): void {
    try { $pdo->prepare("UPDATE contract_settings SET last_run = NULL WHERE company_id = ?")->execute([cid()]); } catch (Throwable $e) { /* table not there yet */ }
}

function contracts_save_settings(PDO $pdo, array $b): array {
    $cur = contracts_settings($pdo);
    $days = isset($b['remind_days']) ? (is_array($b['remind_days']) ? implode(',', $b['remind_days']) : (string)$b['remind_days']) : $cur['remind_days'];
    $days = implode(',', contracts_days($days));
    $flag = fn(string $k) => array_key_exists($k, $b) ? (empty($b[$k]) ? 0 : 1) : (int)$cur[$k];
    $pdo->prepare("INSERT INTO contract_settings (company_id, remind_days, notify_hr, notify_manager, notify_employee, email_hr, remind_expired, last_run)
                   VALUES (?,?,?,?,?,?,?,NULL)
                   ON DUPLICATE KEY UPDATE remind_days = VALUES(remind_days), notify_hr = VALUES(notify_hr), notify_manager = VALUES(notify_manager),
                       notify_employee = VALUES(notify_employee), email_hr = VALUES(email_hr), remind_expired = VALUES(remind_expired), last_run = NULL")
        ->execute([cid(), $days, $flag('notify_hr'), $flag('notify_manager'), $flag('notify_employee'), $flag('email_hr'), $flag('remind_expired')]);
    return contracts_settings($pdo);
}

/** Employees whose contract ends within $days (or already ended) and who still work here. */
function contracts_expiring(PDO $pdo, int $days): array {
    $today = att_now($pdo)->format('Y-m-d');
    $s = $pdo->prepare(
        "SELECT e.id, e.first_name, e.last_name, e.position, e.contract_type, e.contract_start, e.contract_end, d.name AS department_name,
                DATEDIFF(e.contract_end, ?) AS days_left
         FROM employees e LEFT JOIN departments d ON d.id = e.department_id
         WHERE e.company_id = ? AND e.status != 'inactive' AND e.contract_end IS NOT NULL AND e.contract_end <= DATE_ADD(?, INTERVAL ? DAY)
         ORDER BY e.contract_end ASC, e.first_name LIMIT 300"
    );
    $s->execute([$today, cid(), $today, $days]);
    return $s->fetchAll();
}

function contracts_tick(PDO $pdo): void {
    try {
        $st = contracts_settings($pdo);
        $today = att_now($pdo)->format('Y-m-d');
        if (($st['last_run'] ?? null) === $today) return;
        $stages = contracts_days((string)$st['remind_days']);
        $rows = contracts_expiring($pdo, $stages ? max($stages) : 0);
        $hrEmails = [];
        if (!empty($st['email_hr'])) {
            $u = $pdo->prepare("SELECT email FROM users WHERE company_id = ? AND role IN ('hr_admin','hr_manager') AND status = 'active' AND email IS NOT NULL");
            $u->execute([cid()]);
            $hrEmails = $u->fetchAll(PDO::FETCH_COLUMN);
        }
        foreach ($rows as $r) {
            $left = (int)$r['days_left'];
            if ($left >= 0) {
                $stage = null;
                foreach ($stages as $d) if ($d >= $left) $stage = $d;       // the closest reminder day not yet passed
                if ($stage === null) continue;
            } else {
                if (empty($st['remind_expired'])) continue;
                $stage = -1 - intdiv(-$left - 1, 7);                         // one reminder a week while it stays expired
            }
            $ins = $pdo->prepare("INSERT IGNORE INTO contract_alerts (company_id, employee_id, contract_end, days_before) VALUES (?,?,?,?)");
            $ins->execute([cid(), $r['id'], $r['contract_end'], $stage]);
            if ($ins->rowCount() !== 1) continue;                            // already reminded for this stage

            $who = trim($r['first_name'] . ' ' . $r['last_name']);
            $when = $left > 0 ? "ends in $left day" . ($left === 1 ? '' : 's') : ($left === 0 ? 'ends today' : 'ended ' . (-$left) . ' day' . ($left === -1 ? '' : 's') . ' ago');
            $title = $left >= 0 ? 'Contract ending soon' : 'Contract expired';
            $body = "$who's contract $when (" . $r['contract_end'] . "). Renew it or arrange the exit.";
            $data = ['employee_id' => (int)$r['id'], 'days_left' => $left, 'contract_end' => $r['contract_end']];
            if (!empty($st['notify_hr']))       notify_hr($pdo, 'contract_expiry', $title, $body, $data);
            if (!empty($st['notify_manager']))  notify_manager_of($pdo, (int)$r['id'], 'contract_expiry', $title, $body, $data);
            if (!empty($st['notify_employee'])) notify_employee($pdo, (int)$r['id'], 'contract_expiry', $title, "Your contract $when (" . $r['contract_end'] . ').', $data);
            if ($hrEmails) {
                require_once __DIR__ . '/mailer.php';
                $company = (string)(company_get($pdo, cid())['name'] ?? 'Al Anad HR');
                $html = mail_template($company, $title, $left >= 0 ? 'عقد موظف يقترب من نهايته' : 'انتهى عقد موظف', $body, "$who — " . $r['contract_end']);
                foreach ($hrEmails as $to) mail_send((string)$to, "$company: $title", $html, $company);
            }
        }
        $pdo->prepare("INSERT INTO contract_settings (company_id, last_run) VALUES (?, ?) ON DUPLICATE KEY UPDATE last_run = VALUES(last_run)")->execute([cid(), $today]);
    } catch (Throwable $e) {
        error_log('contracts_tick: ' . $e->getMessage());          // never break the notification call
    }
}
