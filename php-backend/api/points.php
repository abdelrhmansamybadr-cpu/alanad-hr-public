<?php
/**
 * Reward points (company-scoped)
 *
 *   GET  /points/me                     caller's summary: colours, net score, streak, level, history
 *   GET  /points/employee/{id}          summary of one employee (HR / direct manager)
 *   GET  /points/leaderboard            ranking (employees see it only if the company allows it)
 *   GET  /points/config                 rules
 *   PUT  /points/config                 (admin) change the rules
 *   POST /points/adjust                 (HR) {employee_id, color, note?, date?} add a point by hand
 *   PUT  /points/{id}                   (HR) {voided: true|false} excuse / restore a day
 *   POST /points/recalculate            (admin) rebuild the automatic points from attendance
 */
require_once __DIR__ . '/../helpers/points.php';

function handle_points(string $path, string $method, array $body): void {
    $pdo = getDB();
    $seg = explode('/', $path);
    $sub = $seg[1] ?? '';

    if ($sub === 'me' && $method === 'GET') {
        $id = own_employee_id();
        if ($id <= 0) error_response('No employee record linked to this account', 404);
        json_response(['success' => true, 'data' => points_summary($pdo, $id)]);
    }
    if ($sub === 'employee' && $method === 'GET' && isset($seg[2]) && ctype_digit($seg[2])) {
        $id = intval($seg[2]);
        if (!employee_in_company($pdo, $id)) error_response('Employee not found', 404);
        if (!can_review_for($pdo, $id) && $id !== own_employee_id()) error_response('Forbidden. Insufficient permissions.', 403);
        json_response(['success' => true, 'data' => points_summary($pdo, $id)]);
    }
    if ($sub === 'leaderboard' && $method === 'GET') {
        $cfg = points_config($pdo);
        if (!is_hr() && !$cfg['show_leaderboard']) error_response('The leaderboard is turned off.', 403);
        json_response(['success' => true, 'data' => ['enabled' => (bool)$cfg['enabled'], 'items' => points_leaderboard($pdo, 100)]]);
    }
    if ($sub === 'config') {
        if ($method === 'GET') json_response(['success' => true, 'data' => points_config($pdo)]);
        if ($method === 'PUT') { require_admin(); points_config_save($body, $pdo); }
        error_response('Method not allowed', 405);
    }
    if ($sub === 'adjust' && $method === 'POST') { require_hr(); points_adjust($body, $pdo); }
    if ($sub === 'recalculate' && $method === 'POST') { require_admin(); points_recalculate($body, $pdo); }
    if ($sub !== '' && ctype_digit($sub) && $method === 'PUT') { require_hr(); points_void(intval($sub), $body, $pdo); }
    error_response('Not found', 404);
}

function points_config_save(array $body, PDO $pdo): void {
    $current = points_config($pdo);
    $new = policy_clean('points_config', $body, $current);
    $pdo->prepare("UPDATE companies SET points_config = ? WHERE id = ?")->execute([json_encode($new), cid()]);
    $GLOBALS['HR_POLICY_CACHE'] = [];
    audit($pdo, 'update', 'points_config', null, $new);
    json_response(['success' => true, 'data' => points_config($pdo)]);
}

function points_adjust(array $body, PDO $pdo): void {
    $employeeId = intval($body['employee_id'] ?? 0);
    $color = (string)($body['color'] ?? '');
    if (!employee_in_company($pdo, $employeeId)) error_response('Employee not found', 404);
    if (!in_array($color, ['green', 'red', 'black'], true)) error_response('Colour must be green, red or black', 422);
    $date = !empty($body['date']) ? $body['date'] : points_today($pdo);
    $note = isset($body['note']) ? mb_substr(trim((string)$body['note']), 0, 255) : null;

    $pdo->prepare("INSERT INTO points_ledger (company_id, employee_id, date, color, reason, source, note, created_by) VALUES (?,?,?,?,'manual','manual',?,?)")
        ->execute([cid(), $employeeId, $date, $color, $note, (int)me()['id']]);
    $labels = ['green' => 'a green point', 'red' => 'a red point', 'black' => 'a black point'];
    notify_employee($pdo, $employeeId, 'points', $color === 'green' ? 'Well done!' : 'Points update',
        'HR gave you ' . $labels[$color] . ($note ? ": $note" : '.'), ['color' => $color]);
    audit($pdo, 'adjust', 'points', $employeeId, ['color' => $color, 'note' => $note]);
    json_response(['success' => true, 'data' => points_summary($pdo, $employeeId)], 201);
}

function points_void(int $id, array $body, PDO $pdo): void {
    $s = $pdo->prepare("SELECT * FROM points_ledger WHERE id = ? AND company_id = ?");
    $s->execute([$id, cid()]);
    $row = $s->fetch();
    if (!$row) error_response('Point not found', 404);
    $v = !empty($body['voided']) ? 1 : 0;
    $pdo->prepare("UPDATE points_ledger SET voided = ? WHERE id = ? AND company_id = ?")->execute([$v, $id, cid()]);
    audit($pdo, $v ? 'excuse' : 'restore', 'points', (int)$row['employee_id'], ['date' => $row['date'], 'color' => $row['color']]);
    json_response(['success' => true, 'data' => points_summary($pdo, (int)$row['employee_id'])]);
}

function points_recalculate(array $body, PDO $pdo): void {
    $cfg = points_config($pdo);
    $only = int_or_null($body['employee_id'] ?? null);
    $q = "SELECT e.id FROM employees e JOIN employee_levels l ON l.employee_id = e.id WHERE e.company_id = ?";
    $args = [cid()];
    if ($only) { $q .= " AND e.id = ?"; $args[] = $only; }
    $s = $pdo->prepare($q);
    $s->execute($args);
    $today = points_today($pdo);
    $yesterday = (new DateTime($today))->modify('-1 day')->format('Y-m-d');
    $done = 0;
    foreach ($s->fetchAll(PDO::FETCH_COLUMN) as $empId) {
        $emp = att_employee_row($pdo, (int)$empId);
        if (!$emp) continue;
        att_close_stale($pdo, (int)$empId);
        $first = $pdo->prepare("SELECT MIN(date) FROM points_ledger WHERE employee_id = ? AND source = 'auto'");
        $first->execute([$empId]);
        $start = $first->fetchColumn();
        if (!$start) { points_sync_employee($pdo, (int)$empId); continue; }
        $n = 0;
        for ($d = new DateTime($start); $d->format('Y-m-d') <= $yesterday && $n < 400; $d->modify('+1 day'), $n++) {
            $ds = $d->format('Y-m-d');
            $r = points_day_color($pdo, $emp, $ds, $cfg, $today);
            if ($r === null) $pdo->prepare("DELETE FROM points_ledger WHERE employee_id = ? AND auto_key = ? AND source = 'auto' AND voided = 0")->execute([$empId, $ds]);
            else points_upsert_auto($pdo, (int)$empId, $ds, $r[0], $r[1]);
        }
        $done++;
    }
    audit($pdo, 'recalculate', 'points', $only, ['employees' => $done]);
    json_response(['success' => true, 'data' => ['employees' => $done]]);
}
