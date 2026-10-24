<?php
/**
 * Payroll extras on top of the attendance-based computation:
 *   - social insurance and income tax (settings in the payroll policy; all off by default)
 *   - loans / salary advances repaid in monthly instalments
 *   - printable payslip: a signed, short-lived link that opens an HTML page (print -> save as PDF)
 */

// ------------------------------------------------------------------ tax and insurance

/** Monthly progressive tax from steps like "5000|0", "10000|10", "|20" (empty limit = everything above). */
function payroll_progressive_tax(array $brackets, float $taxable): float {
    $steps = [];
    foreach ($brackets as $b) {
        [$limit, $rate] = array_pad(explode('|', (string)$b, 2), 2, '0');
        $steps[] = [$limit === '' ? null : (float)$limit, (float)$rate];
    }
    usort($steps, fn($a, $b) => ($a[0] ?? INF) <=> ($b[0] ?? INF));
    $tax = 0.0; $from = 0.0;
    foreach ($steps as [$limit, $rate]) {
        $upper = $limit ?? INF;
        if ($taxable > $from) $tax += (min($taxable, $upper) - $from) * $rate / 100;
        if ($taxable <= $upper) break;
        $from = $upper;
    }
    return round($tax, 2);
}

// ------------------------------------------------------------------ loans

function payroll_loan_paid_before(PDO $pdo, int $employeeId, int $month, int $year): array {
    $s = $pdo->prepare("SELECT month, year, breakdown FROM payroll WHERE company_id = ? AND employee_id = ? AND status != 'cancelled' AND breakdown IS NOT NULL AND (year * 12 + month) < ?");
    $s->execute([cid(), $employeeId, $year * 12 + $month]);
    $paid = [];
    foreach ($s->fetchAll() as $row) {
        $bd = json_decode((string)$row['breakdown'], true);
        foreach (($bd['lines'] ?? []) as $l) {
            if (preg_match('/^loan_(\d+)$/', (string)($l['key'] ?? ''), $m)) $paid[(int)$m[1]] = ($paid[(int)$m[1]] ?? 0) + abs((float)$l['amount']);
        }
    }
    return $paid;
}

/** The instalments due in a month: [lines, total]. Derived from earlier payslips, so recalculating never double-charges. */
function payroll_loan_lines(PDO $pdo, int $employeeId, int $month, int $year): array {
    $s = $pdo->prepare("SELECT * FROM payroll_loans WHERE company_id = ? AND employee_id = ? AND status = 'active' AND start_month <= ? ORDER BY id");
    $s->execute([cid(), $employeeId, sprintf('%04d-%02d', $year, $month)]);
    $loans = $s->fetchAll();
    if (!$loans) return [[], 0.0];
    $paid = payroll_loan_paid_before($pdo, $employeeId, $month, $year);
    $lines = []; $total = 0.0;
    foreach ($loans as $l) {
        $remaining = (float)$l['amount'] - ($paid[(int)$l['id']] ?? 0);
        if ($remaining <= 0.004) continue;
        $take = round(min((float)$l['installment'], $remaining), 2);
        $lines[] = ['key' => 'loan_' . $l['id'], 'label' => 'Loan: ' . $l['title'], 'qty' => 1, 'amount' => -$take];
        $total += $take;
    }
    return [$lines, round($total, 2)];
}

/** Adds insurance, tax and loan instalments to a computed payslip. Returns [base, bonus, totalDeductions, breakdown]. */
function payroll_finish(PDO $pdo, array $emp, int $month, int $year, float $base, float $bonus, float $ded, ?array $bd): array {
    $pol = payroll_policy($pdo);
    $lines = $bd['lines'] ?? [];
    $extra = 0.0;

    $insurance = 0.0;
    if ((float)$pol['insurance_pct'] > 0) {
        $insurable = (float)$pol['insurance_cap'] > 0 ? min($base, (float)$pol['insurance_cap']) : $base;
        $insurance = round($insurable * (float)$pol['insurance_pct'] / 100, 2);
        if ($insurance > 0) { $lines[] = ['key' => 'insurance', 'label' => 'Social insurance', 'qty' => round((float)$pol['insurance_pct'], 2), 'amount' => -$insurance]; $extra += $insurance; }
    }

    if (($pol['tax_mode'] ?? 'none') !== 'none') {
        $taxable = max(0.0, $base + $bonus - $ded - $insurance - (float)$pol['tax_monthly_exemption']);
        $tax = $pol['tax_mode'] === 'flat' ? round($taxable * (float)$pol['tax_flat_pct'] / 100, 2) : payroll_progressive_tax((array)$pol['tax_brackets'], $taxable);
        if ($tax > 0) { $lines[] = ['key' => 'tax', 'label' => 'Income tax', 'qty' => 1, 'amount' => -$tax]; $extra += $tax; }
    }

    [$loanLines, $loanTotal] = payroll_loan_lines($pdo, (int)$emp['id'], $month, $year);
    foreach ($loanLines as $l) $lines[] = $l;
    $extra += $loanTotal;

    $stats = $bd['stats'] ?? null;
    if (!$lines && $stats === null) return [$base, round($bonus, 2), round($ded, 2), null];
    return [$base, round($bonus, 2), round($ded + $extra, 2), ['lines' => $lines, 'stats' => $stats]];
}

// ------------------------------------------------------------------ loans API  (/payroll/loans)

function payroll_loans_with_balance(PDO $pdo, array $rows): array {
    $out = [];
    $cache = [];
    foreach ($rows as $r) {
        $eid = (int)$r['employee_id'];
        if (!isset($cache[$eid])) $cache[$eid] = payroll_loan_paid_before($pdo, $eid, 12, 9999);      // everything generated so far
        $paid = round($cache[$eid][(int)$r['id']] ?? 0, 2);
        $remaining = max(0, round((float)$r['amount'] - $paid, 2));
        $r['paid'] = $paid;
        $r['remaining'] = $remaining;
        if ($r['status'] === 'active' && $remaining <= 0.004) $r['status'] = 'done';
        $out[] = $r;
    }
    return $out;
}

function payroll_loans_handle(array $segments, string $method, array $body, PDO $pdo): void {
    $id = isset($segments[2]) && ctype_digit($segments[2]) ? intval($segments[2]) : null;

    if ($method === 'GET' && $id === null) {
        $where = ['l.company_id = ?']; $params = [cid()];
        if (!is_hr()) { $where[] = 'l.employee_id = ?'; $params[] = own_employee_id(); }
        elseif (!empty($_GET['employee_id'])) { $where[] = 'l.employee_id = ?'; $params[] = intval($_GET['employee_id']); }
        $s = $pdo->prepare("SELECT l.*, CONCAT(e.first_name, ' ', e.last_name) AS employee_name FROM payroll_loans l JOIN employees e ON e.id = l.employee_id WHERE " . implode(' AND ', $where) . " ORDER BY l.id DESC");
        $s->execute($params);
        json_response(['success' => true, 'data' => payroll_loans_with_balance($pdo, $s->fetchAll())]);
    }
    require_hr();
    if ($method === 'POST' && $id === null) {
        $eid = (int)($body['employee_id'] ?? 0);
        $title = trim((string)($body['title'] ?? ''));
        $amount = round((float)($body['amount'] ?? 0), 2);
        $inst = round((float)($body['installment'] ?? 0), 2);
        $start = (string)($body['start_month'] ?? date('Y-m'));
        if (!$eid || !employee_in_company($pdo, $eid)) error_response('Choose an employee', 422);
        if ($title === '' || mb_strlen($title) > 150) error_response('A short title is required', 422);
        if ($amount <= 0) error_response('The amount must be more than zero', 422);
        if ($inst <= 0 || $inst > $amount) error_response('The monthly instalment must be more than zero and not more than the amount', 422);
        if (!preg_match('/^\d{4}-(0[1-9]|1[0-2])$/', $start)) error_response('Start month must be YYYY-MM', 422);
        $pdo->prepare("INSERT INTO payroll_loans (company_id, employee_id, title, amount, installment, start_month, created_by) VALUES (?,?,?,?,?,?,?)")
            ->execute([cid(), $eid, $title, $amount, $inst, $start, (int)me()['id']]);
        $newId = (int)$pdo->lastInsertId();
        audit($pdo, 'create', 'payroll_loan', $newId, ['employee_id' => $eid, 'amount' => $amount, 'installment' => $inst]);
        notify_employee($pdo, $eid, 'loan', 'A loan was added', "$title: $amount, repaid $inst a month from $start.", ['loan_id' => $newId]);
        $r = $pdo->prepare("SELECT l.*, CONCAT(e.first_name, ' ', e.last_name) AS employee_name FROM payroll_loans l JOIN employees e ON e.id = l.employee_id WHERE l.id = ?");
        $r->execute([$newId]);
        json_response(['success' => true, 'data' => payroll_loans_with_balance($pdo, [$r->fetch()])[0]], 201);
    }
    if ($method === 'PUT' && $id !== null) {
        $s = $pdo->prepare("SELECT * FROM payroll_loans WHERE id = ? AND company_id = ?");
        $s->execute([$id, cid()]);
        $loan = $s->fetch();
        if (!$loan) error_response('Loan not found', 404);
        $status = $body['status'] ?? $loan['status'];
        if (!in_array($status, ['active', 'cancelled'], true)) error_response('Invalid status', 422);
        $inst = isset($body['installment']) ? round((float)$body['installment'], 2) : (float)$loan['installment'];
        if ($inst <= 0 || $inst > (float)$loan['amount']) error_response('Invalid instalment', 422);
        $title = isset($body['title']) ? trim((string)$body['title']) : $loan['title'];
        if ($title === '') error_response('A short title is required', 422);
        $pdo->prepare("UPDATE payroll_loans SET status = ?, installment = ?, title = ? WHERE id = ? AND company_id = ?")->execute([$status, $inst, $title, $id, cid()]);
        audit($pdo, 'update', 'payroll_loan', $id, ['status' => $status, 'installment' => $inst]);
        $r = $pdo->prepare("SELECT l.*, CONCAT(e.first_name, ' ', e.last_name) AS employee_name FROM payroll_loans l JOIN employees e ON e.id = l.employee_id WHERE l.id = ?");
        $r->execute([$id]);
        json_response(['success' => true, 'data' => payroll_loans_with_balance($pdo, [$r->fetch()])[0]]);
    }
    error_response('Not found', 404);
}

// ------------------------------------------------------------------ printable payslip

function payslip_secret(PDO $pdo): string {
    $s = $pdo->prepare("SELECT value FROM app_secrets WHERE name = 'payslip_link'");
    $s->execute();
    $v = $s->fetchColumn();
    if ($v) return (string)$v;
    $v = bin2hex(random_bytes(32));
    $pdo->prepare("INSERT IGNORE INTO app_secrets (name, value) VALUES ('payslip_link', ?)")->execute([$v]);
    $s->execute();
    return (string)$s->fetchColumn();
}

function payslip_token(PDO $pdo, int $payrollId, int $companyId, int $ttl = 600): string {
    $payload = $payrollId . '.' . $companyId . '.' . (time() + $ttl);
    return rtrim(strtr(base64_encode($payload), '+/', '-_'), '=') . '.' . hash_hmac('sha256', $payload, payslip_secret($pdo));
}

/** Returns [payrollId, companyId] for a valid, unexpired token, otherwise null. */
function payslip_token_check(PDO $pdo, string $token): ?array {
    $parts = explode('.', $token, 2);
    if (count($parts) !== 2) return null;
    $payload = base64_decode(strtr($parts[0], '-_', '+/'), true);
    if ($payload === false || !preg_match('/^(\d+)\.(\d+)\.(\d+)$/', $payload, $m)) return null;
    if (!hash_equals(hash_hmac('sha256', $payload, payslip_secret($pdo)), $parts[1])) return null;
    if ((int)$m[3] < time()) return null;
    return [(int)$m[1], (int)$m[2]];
}

/** GET /payroll/{id}/link?lang=en|ar  ->  {url, expires_in} */
function payroll_payslip_link(int $id, PDO $pdo): void {
    $row = payroll_fetch($id, $pdo);
    if (!$row) error_response('Payroll record not found', 404);
    if (!is_hr() && (int)$row['employee_id'] !== own_employee_id()) error_response('Forbidden. Insufficient permissions.', 403);
    $lang = ($_GET['lang'] ?? 'en') === 'ar' ? 'ar' : 'en';
    $base = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off' ? 'https://' : 'http://') . ($_SERVER['HTTP_HOST'] ?? 'localhost');
    json_response(['success' => true, 'data' => ['url' => $base . '/payslip-view?t=' . payslip_token($pdo, $id, cid()) . '&lang=' . $lang, 'expires_in' => 600]]);
}
