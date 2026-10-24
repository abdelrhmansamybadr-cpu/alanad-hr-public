<?php
/**
 * Employee requests (company-scoped): expenses, certificates, attendance corrections,
 * profile changes, equipment, other.
 *
 *   GET  /requests?status=&type=&employee_id=&scope=team   list (HR: all; employee: own; team lead: scope=team)
 *   GET  /requests/{id}
 *   POST /requests                                          {type, title, description?, amount?, payload?}
 *   PUT  /requests/{id}                                     {status: approved|rejected, review_note} (HR / direct manager)
 *                                                           {status: cancelled} (owner, while pending)
 *
 *  - profile_change        payload {changes: {phone: "...", address: "..."}}     applied to the employee when HR approves
 *  - attendance_correction payload {date, check_in, check_out, reason}           that day's attendance is rewritten when HR approves
 *
 * Employees cannot edit HR-entered data or their own attendance status directly: they ask here.
 */
require_once __DIR__ . '/attendance.php';

function requests_types(): array {
    return ['expense', 'certificate', 'attendance_correction', 'profile_change', 'equipment', 'other'];
}

function requests_profile_fields(): array {
    return ['first_name', 'last_name', 'phone', 'address', 'birth_date', 'gender', 'emergency_name', 'emergency_phone'];
}

function handle_requests(string $path, string $method, array $body): void {
    $pdo = getDB();
    $sub = explode('/', $path)[1] ?? '';
    $id  = ($sub !== '' && is_numeric($sub)) ? intval($sub) : null;

    if ($id !== null) {
        switch ($method) {
            case 'GET': requests_get_one($id, $pdo, true); break;
            case 'PUT': requests_update($id, $body, $pdo); break;
            default:    error_response('Method not allowed', 405);
        }
        return;
    }
    switch ($method) {
        case 'GET':  requests_list($pdo); break;
        case 'POST': requests_create($body, $pdo); break;
        default:     error_response('Method not allowed', 405);
    }
}

function requests_select(): string {
    return "SELECT r.*, CONCAT(e.first_name, ' ', e.last_name) AS employee_name, e.avatar AS employee_avatar,
                   e.department_id, d.name AS department_name,
                   rv.name AS reviewed_by_name
            FROM requests r
            JOIN employees e ON e.id = r.employee_id
            LEFT JOIN departments d ON d.id = e.department_id
            LEFT JOIN users rv ON rv.id = r.reviewed_by";
}

function requests_decode(array $r): array {
    $r['payload'] = !empty($r['payload']) ? json_decode($r['payload'], true) : null;
    return $r;
}

function requests_fetch(int $id, PDO $pdo): ?array {
    $s = $pdo->prepare(requests_select() . " WHERE r.id = ? AND r.company_id = ?");
    $s->execute([$id, cid()]);
    $r = $s->fetch();
    return $r ? requests_decode($r) : null;
}

function requests_list(PDO $pdo): void {
    $where  = ['r.company_id = ?'];
    $params = [cid()];

    if (!is_hr()) {
        if (($_GET['scope'] ?? '') === 'team') { $where[] = 'e.manager_id = ?';   $params[] = own_employee_id(); }
        else                                    { $where[] = 'r.employee_id = ?';  $params[] = own_employee_id(); }
    } elseif (!empty($_GET['employee_id'])) {
        $where[] = 'r.employee_id = ?'; $params[] = intval($_GET['employee_id']);
    }
    if (!empty($_GET['status'])) { $where[] = 'r.status = ?'; $params[] = $_GET['status']; }
    if (!empty($_GET['type']))   { $where[] = 'r.type = ?';   $params[] = $_GET['type']; }

    $s = $pdo->prepare(requests_select() . " WHERE " . implode(' AND ', $where) . " ORDER BY r.created_at DESC, r.id DESC LIMIT 300");
    $s->execute($params);
    json_response(['success' => true, 'data' => array_map('requests_decode', $s->fetchAll())]);
}

function requests_get_one(int $id, PDO $pdo, bool $respond = false): ?array {
    $r = requests_fetch($id, $pdo);
    if (!$r) error_response('Request not found', 404);
    if (!is_hr() && (int)$r['employee_id'] !== own_employee_id() && !is_manager_of($pdo, (int)$r['employee_id'])) {
        error_response('Forbidden. Insufficient permissions.', 403);
    }
    if ($respond) json_response(['success' => true, 'data' => $r]);
    return $r;
}

function requests_create(array $body, PDO $pdo): void {
    $employeeId = is_hr() && !empty($body['employee_id']) ? intval($body['employee_id']) : own_employee_id();
    if ($employeeId <= 0 || !employee_in_company($pdo, $employeeId)) error_response('No employee record linked to this account', 404);

    $type  = (string)($body['type'] ?? '');
    $title = trim((string)($body['title'] ?? ''));
    if (!in_array($type, requests_types(), true)) error_response('Invalid request type', 422);
    $amount = isset($body['amount']) && $body['amount'] !== '' ? floatval($body['amount']) : null;
    if ($type === 'expense' && ($amount === null || $amount <= 0)) error_response('Please enter the expense amount', 422);
    $payload = null;

    if ($type === 'profile_change') {
        $in = is_array($body['payload']['changes'] ?? null) ? $body['payload']['changes'] : (is_array($body['changes'] ?? null) ? $body['changes'] : []);
        $cur = $pdo->prepare("SELECT * FROM employees WHERE id = ? AND company_id = ?");
        $cur->execute([$employeeId, cid()]);
        $emp = $cur->fetch();
        $changes = [];
        foreach (requests_profile_fields() as $f) {
            if (!array_key_exists($f, $in)) continue;
            $to = trim((string)$in[$f]);
            if ($f === 'birth_date' && $to !== '') {
                $d = DateTime::createFromFormat('Y-m-d', $to);
                if (!$d || $d->format('Y-m-d') !== $to) error_response('Birth date must be YYYY-MM-DD', 422);
            }
            if (in_array($f, ['first_name', 'last_name'], true) && $to === '') error_response('Name cannot be empty', 422);
            $from = (string)($emp[$f] ?? '');
            if ($to !== $from) $changes[$f] = ['from' => $from, 'to' => mb_substr($to, 0, 500)];
        }
        if (!$changes) error_response('Nothing to change. Edit at least one field.', 422);
        $payload = ['changes' => $changes];
        if ($title === '') $title = 'Update my information';
        if (empty($body['description'])) $body['description'] = implode(', ', array_keys($changes));
    } elseif ($type === 'attendance_correction') {
        $pl = is_array($body['payload'] ?? null) ? $body['payload'] : [];
        $date = (string)($pl['date'] ?? '');
        $d = DateTime::createFromFormat('Y-m-d', $date);
        if (!$d || $d->format('Y-m-d') !== $date) error_response('Choose the date to correct', 422);
        $today = att_now($pdo);
        if ($date > $today->format('Y-m-d')) error_response('You cannot correct a future day', 422);
        if ($date < (clone $today)->modify('-45 days')->format('Y-m-d')) error_response('Only the last 45 days can be corrected', 422);
        $in  = (string)($pl['check_in'] ?? '');
        $out = (string)($pl['check_out'] ?? '');
        foreach ([$in, $out] as $t) {
            if ($t !== '' && !preg_match('/^\d{2}:\d{2}(:\d{2})?$/', $t)) error_response('Times must look like 09:00', 422);
        }
        if ($in === '') error_response('Enter the time you arrived', 422);
        $payload = ['date' => $date, 'check_in' => substr($in, 0, 5), 'check_out' => $out !== '' ? substr($out, 0, 5) : null,
                    'reason' => mb_substr(trim((string)($pl['reason'] ?? '')), 0, 500)];
        if ($title === '') $title = 'Attendance correction for ' . $date;
        $dup = $pdo->prepare("SELECT 1 FROM requests WHERE company_id = ? AND employee_id = ? AND type = 'attendance_correction' AND status = 'pending' AND payload LIKE ? LIMIT 1");
        $dup->execute([cid(), $employeeId, '%"date":"' . $date . '"%']);
        if ($dup->fetchColumn()) error_response('You already have a pending correction for this day.', 409);
    }
    if ($title === '' || mb_strlen($title) > 200) error_response('A short title is required', 422);

    $headStatus = function_exists('chain_start_status') && in_array($type, chain_request_types(), true)
        ? chain_start_status($pdo, $employeeId) : null;      // two-step approvals: the team head first
    $pdo->prepare("INSERT INTO requests (company_id, employee_id, type, title, description, amount, payload, head_status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
        ->execute([cid(), $employeeId, $type, $title, $body['description'] ?? null, $amount, $payload ? json_encode($payload, JSON_UNESCAPED_UNICODE) : null, $headStatus]);
    $newId = (int)$pdo->lastInsertId();

    $who = $pdo->prepare("SELECT CONCAT(first_name, ' ', last_name) FROM employees WHERE id = ?");
    $who->execute([$employeeId]);
    $msg = $who->fetchColumn() . ': ' . $title;
    if (!in_array($type, ['profile_change', 'attendance_correction'], true)) {
        notify_manager_of($pdo, $employeeId, 'request', 'New request', $msg, ['request_id' => $newId]);
    }
    if ($headStatus === null) notify_hr($pdo, 'request', 'New request', $msg, ['request_id' => $newId], (int)me()['id']);

    json_response(['success' => true, 'data' => requests_fetch($newId, $pdo)], 201);
}

/** Apply an approved request's payload to the real data. */
function requests_apply(PDO $pdo, array $r): void {
    $pl = $r['payload'] ?? null;
    if (!is_array($pl)) return;
    $employeeId = (int)$r['employee_id'];

    if ($r['type'] === 'profile_change' && !empty($pl['changes'])) {
        $f = []; $p = [];
        foreach ($pl['changes'] as $col => $ch) {
            if (!in_array($col, requests_profile_fields(), true)) continue;
            $f[] = "$col = ?";
            $p[] = $ch['to'] === '' ? null : $ch['to'];
        }
        if ($f) {
            $p[] = $employeeId; $p[] = cid();
            $pdo->prepare("UPDATE employees SET " . implode(', ', $f) . " WHERE id = ? AND company_id = ?")->execute($p);
        }
        if (isset($pl['changes']['phone'])) {
            $pdo->prepare("UPDATE users SET phone = ? WHERE employee_id = ? AND company_id = ?")->execute([$pl['changes']['phone']['to'] ?: null, $employeeId, cid()]);
        }
        if (isset($pl['changes']['first_name']) || isset($pl['changes']['last_name'])) {
            $e = $pdo->prepare("SELECT CONCAT(first_name, ' ', last_name) FROM employees WHERE id = ?");
            $e->execute([$employeeId]);
            $pdo->prepare("UPDATE users SET name = ? WHERE employee_id = ? AND company_id = ? AND role = 'employee'")->execute([$e->fetchColumn(), $employeeId, cid()]);
        }
    }

    if ($r['type'] === 'attendance_correction') {
        $date = $pl['date'];
        $in   = $pl['check_in'] . ':00';
        $out  = !empty($pl['check_out']) ? $pl['check_out'] . ':00' : null;
        $ex = $pdo->prepare("SELECT * FROM attendance WHERE company_id = ? AND employee_id = ? AND date = ? LIMIT 1");
        $ex->execute([cid(), $employeeId, $date]);
        $rec  = $ex->fetch();
        $note = 'Corrected: ' . ($pl['reason'] ?? '');
        if ($rec) {
            $pdo->prepare("UPDATE attendance SET check_in = ?, check_out = ?, closed = 1, source = 'correction', note = ?, out_zone_minutes = 0, edited_by = ? WHERE id = ? AND company_id = ?")
                ->execute([$in, $out, $note, (int)me()['id'], $rec['id'], cid()]);
            $id = (int)$rec['id'];
        } else {
            $pdo->prepare("INSERT INTO attendance (company_id, employee_id, date, check_in, check_out, status, source, note, closed, edited_by) VALUES (?,?,?,?,?,'present','correction',?,1,?)")
                ->execute([cid(), $employeeId, $date, $in, $out, $note, (int)me()['id']]);
            $id = (int)$pdo->lastInsertId();
        }
        att_apply($pdo, attendance_fetch($id, $pdo), null, true);
        points_reeval_safe($pdo, $employeeId, $date);
    }
}

function requests_update(int $id, array $body, PDO $pdo): void {
    $r = requests_get_one($id, $pdo);
    $employeeId = (int)$r['employee_id'];
    $isOwner    = $employeeId === own_employee_id();
    $status     = $body['status'] ?? null;
    if (!in_array($status, ['approved', 'rejected', 'cancelled'], true)) error_response('Invalid status', 422);
    if ($r['status'] !== 'pending') error_response('This request has already been handled.', 409);

    if ($status === 'cancelled') {
        if (!$isOwner && !is_hr()) error_response('Forbidden. Insufficient permissions.', 403);
    } else {
        if (!can_review_for($pdo, $employeeId) || ($isOwner && !is_hr())) error_response('Forbidden. Only HR or the direct manager can review this request.', 403);
        if (in_array($r['type'], ['profile_change', 'attendance_correction'], true) && !is_hr()) error_response('Only HR can review this kind of request.', 403);
    }

    if ($status !== 'cancelled' && function_exists('chain_gate') && chain_gate($pdo, 'requests', $r, $status, $body, 'request') === 'head_approved') {
        audit($pdo, 'head_approved', 'request', $id, ['type' => $r['type'], 'employee_id' => $employeeId]);
        json_response(['success' => true, 'data' => requests_fetch($id, $pdo)]);
    }
    if (function_exists('decision_require_reason')) decision_require_reason($pdo, $status, $body['review_note'] ?? null);   // feature fair_decisions
    $pdo->prepare("UPDATE requests SET status = ?, reviewed_by = ?, reviewed_at = NOW(), review_note = ? WHERE id = ? AND company_id = ?")
        ->execute([$status, (int)me()['id'], $body['review_note'] ?? null, $id, cid()]);

    if ($status === 'approved') requests_apply($pdo, $r);
    if ($status !== 'cancelled') audit($pdo, $status, 'request', $id, ['type' => $r['type'], 'employee_id' => $employeeId]);

    if ($status !== 'cancelled' && !$isOwner) {
        $note = !empty($body['review_note']) ? ' Note: ' . $body['review_note'] : '';
        notify_employee($pdo, $employeeId, 'request_' . $status, 'Request ' . $status, "Your request \"{$r['title']}\" was $status.$note", ['request_id' => $id]);
    }
    json_response(['success' => true, 'data' => requests_fetch($id, $pdo)]);
}
