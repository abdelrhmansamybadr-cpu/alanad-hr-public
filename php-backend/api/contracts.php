<?php
/**
 * Contract alarms (HR only)
 *
 *   GET /contracts/settings                 when and whom to remind
 *   PUT /contracts/settings {remindDays:[30,14,7,1], notifyHr, notifyManager, notifyEmployee, emailHr, remindExpired}
 *   GET /contracts/expiring?days=90         contracts that end soon or already ended (+ counts)
 *   POST /contracts/:employeeId/renew {months?|endDate?, type?}   extend a contract
 */
require_once __DIR__ . '/../helpers/policy.php';
require_once __DIR__ . '/../helpers/contracts.php';

function handle_contracts(string $path, string $method, array $body): void {
    require_hr();
    $pdo = getDB();
    $seg = explode('/', $path);
    $sub = $seg[1] ?? '';

    if ($sub === 'settings' && $method === 'GET') {
        json_response(['success' => true, 'data' => contracts_public($pdo)]);
    }
    if ($sub === 'settings' && $method === 'PUT') {
        contracts_save_settings($pdo, $body);
        $s = contracts_public($pdo);
        audit($pdo, 'update', 'contract_settings', null, $s);
        json_response(['success' => true, 'data' => $s]);
    }
    if ($sub === 'expiring' && $method === 'GET') {
        contracts_tick($pdo);
        $days = isset($_GET['days']) ? max(1, min(365, (int)$_GET['days'])) : 90;
        $rows = contracts_expiring($pdo, $days);
        $counts = ['expired' => 0, 'soon' => 0, 'upcoming' => 0];
        foreach ($rows as $r) {
            $l = (int)$r['days_left'];
            if ($l < 0) $counts['expired']++;
            elseif ($l <= 30) $counts['soon']++;
            if ($l >= 0 && $l <= 90) $counts['upcoming']++;
        }
        json_response(['success' => true, 'data' => ['items' => $rows, 'counts' => $counts]]);
    }
    if ($sub !== '' && ctype_digit($sub) && ($seg[2] ?? '') === 'renew' && $method === 'POST') {
        $id = (int)$sub;
        $s = $pdo->prepare("SELECT * FROM employees WHERE id = ? AND company_id = ?");
        $s->execute([$id, cid()]);
        $emp = $s->fetch();
        if (!$emp) error_response('Employee not found', 404);
        $in = [];
        if (!empty($body['type'])) $in['contract_type'] = $body['type'];
        if (!empty($body['end_date'])) {
            $in['contract_end'] = $body['end_date'];
        } elseif (!empty($body['months'])) {
            // extend from the day after the current end (or from today when the contract is already open-ended or missing)
            $from = $emp['contract_end'] ?: att_now($pdo)->format('Y-m-d');
            $m = max(1, min(240, (int)$body['months']));
            $in['contract_end'] = (new DateTime($from))->modify("+$m months")->format('Y-m-d');
            $in['contract_months'] = $m;
        } else {
            error_response('Give the new end date or the number of months', 422);
        }
        if (empty($emp['contract_start'])) $in['contract_start'] = $emp['start_date'] ?: att_now($pdo)->format('Y-m-d');
        if (($in['contract_type'] ?? $emp['contract_type'] ?? 'permanent') === 'permanent') $in['contract_type'] = 'fixed_term';
        $f = contract_fields($in, $emp);
        $set = []; $args = [];
        foreach ($f as $k => $v) { $set[] = "$k = ?"; $args[] = $v; }
        $args[] = $id; $args[] = cid();
        $pdo->prepare("UPDATE employees SET " . implode(', ', $set) . " WHERE id = ? AND company_id = ?")->execute($args);
        contracts_reset($pdo);
        audit($pdo, 'renew_contract', 'employee', $id, $f);
        notify_employee($pdo, $id, 'contract_renewed', 'Contract renewed', 'Your contract now runs until ' . $f['contract_end'] . '.', ['contract_end' => $f['contract_end']]);
        json_response(['success' => true, 'data' => $f]);
    }
    error_response('Not found', 404);
}
