<?php
/**
 * Leaves API handler (company-scoped)
 *
 *   GET    /leaves                 list  (filters: employee_id, status, type, year, month, scope=team)
 *   GET    /leaves/balance         balance per leave type for the caller (HR: ?employee_id=)
 *   GET    /leaves/policy          legacy policy numbers
 *   PUT    /leaves/policy          (admin)
 *   GET    /leaves/analytics[/id]  reports (HR)
 *   GET    /leaves/{id}
 *   POST   /leaves                 request leave
 *   PUT    /leaves/{id}            approve / reject (HR or direct manager) or edit while pending
 *   DELETE /leaves/{id}            employee: cancel own pending request, HR: delete
 */
function handle_leaves(string $path, string $method, array $body): void {
    $pdo      = getDB();
    $segments = explode('/', $path);
    $sub      = $segments[1] ?? '';

    if ($sub === 'policy') {
        switch ($method) {
            case 'GET': leaves_get_policy($pdo); break;
            case 'PUT': require_admin(); leaves_update_policy($body, $pdo); break;
            default:    error_response('Method not allowed', 405);
        }
        return;
    }

    if ($sub === 'balance') {
        if ($method !== 'GET') error_response('Method not allowed', 405);
        leaves_balance_endpoint($pdo);
        return;
    }

    if ($sub === 'analytics') {
        require_hr();
        $employeeId = isset($segments[2]) && is_numeric($segments[2]) ? intval($segments[2]) : null;
        if ($employeeId) {
            leaves_analytics_employee($employeeId, $pdo);
        } else {
            leaves_analytics($pdo);
        }
        return;
    }

    $id = ($sub !== '' && is_numeric($sub)) ? intval($sub) : null;

    if ($id !== null) {
        switch ($method) {
            case 'GET':    leaves_get_one($id, $pdo, true); break;
            case 'PUT':    leaves_update($id, $body, $pdo); break;
            case 'DELETE': leaves_delete($id, $pdo); break;
            default:       error_response('Method not allowed', 405);
        }
    } else {
        switch ($method) {
            case 'GET':  leaves_list($pdo); break;
            case 'POST': leaves_create($body, $pdo); break;
            default:     error_response('Method not allowed', 405);
        }
    }
}

// ------------------------------------------------------------------ helpers

function leaves_select(): string {
    return "SELECT l.*,
                   CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
                   e.avatar AS employee_avatar,
                   e.department_id,
                   d.name AS department_name,
                   lt.name AS type_name,
                   lt.color AS type_color,
                   rv.name AS reviewed_by_name
            FROM leaves l
            JOIN employees e ON e.id = l.employee_id
            LEFT JOIN departments d ON d.id = e.department_id
            LEFT JOIN leave_types lt ON lt.company_id = l.company_id AND lt.code = l.type
            LEFT JOIN users rv ON rv.id = l.reviewed_by";
}

function leaves_fetch(int $id, PDO $pdo): ?array {
    $stmt = $pdo->prepare(leaves_select() . " WHERE l.id = ? AND l.company_id = ?");
    $stmt->execute([$id, cid()]);
    return $stmt->fetch() ?: null;
}

/** Parse Y-m-d strictly; null if invalid. */
function leaves_date(?string $s): ?DateTime {
    if (!$s) return null;
    $d = DateTime::createFromFormat('Y-m-d', substr($s, 0, 10));
    return ($d && $d->format('Y-m-d') === substr($s, 0, 10)) ? $d : null;
}

/** Working days between two dates (inclusive), skipping the company weekend and holidays. */
function leaves_working_days(PDO $pdo, DateTime $start, DateTime $end): int {
    $company = company_get($pdo, cid());
    $weekend = array_map('trim', explode(',', strtolower($company['weekend_days'] ?? 'fri,sat')));

    $h = $pdo->prepare("SELECT date FROM holidays WHERE company_id = ? AND date BETWEEN ? AND ?");
    $h->execute([cid(), $start->format('Y-m-d'), $end->format('Y-m-d')]);
    $holidays = array_flip($h->fetchAll(PDO::FETCH_COLUMN));

    $days = 0;
    $cur  = clone $start;
    while ($cur <= $end) {
        $dow = strtolower($cur->format('D'));      // mon, tue, ...
        if (!in_array($dow, $weekend, true) && !isset($holidays[$cur->format('Y-m-d')])) {
            $days++;
        }
        $cur->modify('+1 day');
    }
    return $days;
}

/** Balance per active leave type for an employee in a year. */
/**
 * Annual leave entitlement by years of service and age, following Egyptian Labour Law No. 12 of 2003:
 * 15 days after 6 months, 21 days after 1 year, 30 days after 10 years of service or from age 50.
 * Offered as an optional preset (attendance policy "leave_preset" = egypt); companies should confirm the
 * figures with their own legal or accounting adviser.
 */
function leaves_egypt_entitlement(?string $startDate, ?string $birthDate, DateTime $asOf): int {
    if (!$startDate) return 21;
    $service = (new DateTime($startDate))->diff($asOf);
    $months = $service->y * 12 + $service->m;
    $age = $birthDate ? (new DateTime($birthDate))->diff($asOf)->y : 0;
    if ($service->y >= 10 || $age >= 50) return 30;
    if ($months >= 12) return 21;
    if ($months >= 6) return 15;
    return 0;
}

function leaves_balance(PDO $pdo, int $employeeId, int $year): array {
    $preset = (att_policy($pdo)['leave_preset'] ?? 'none') === 'egypt' ? true : false;
    $presetDays = null;
    if ($preset) {
        $e = $pdo->prepare("SELECT start_date, birth_date FROM employees WHERE id = ? AND company_id = ?");
        $e->execute([$employeeId, cid()]);
        $er = $e->fetch();
        $today = att_now($pdo);
        $asOf = (int)$today->format('Y') === $year ? $today : new DateTime("$year-12-31");
        $presetDays = leaves_egypt_entitlement($er['start_date'] ?? null, $er['birth_date'] ?? null, $asOf);
    }
    $types = $pdo->prepare("SELECT code, name, color, days_per_year, paid FROM leave_types WHERE company_id = ? AND is_active = 1 ORDER BY id");
    $types->execute([cid()]);

    $used = $pdo->prepare(
        "SELECT type, status, COALESCE(SUM(days), 0) AS d
         FROM leaves
         WHERE company_id = ? AND employee_id = ? AND YEAR(start_date) = ? AND status IN ('approved','pending')
         GROUP BY type, status"
    );
    $used->execute([cid(), $employeeId, $year]);
    $byType = [];
    foreach ($used->fetchAll() as $r) { $byType[$r['type']][$r['status']] = (int)$r['d']; }

    $out = [];
    foreach ($types->fetchAll() as $t) {
        $approved = $byType[$t['code']]['approved'] ?? 0;
        $pending  = $byType[$t['code']]['pending'] ?? 0;
        $total    = (int)$t['days_per_year'];
        $notYet = false;
        if ($presetDays !== null && $t['code'] === 'annual') { $total = $presetDays; $notYet = $presetDays === 0; }     // under 6 months: not entitled yet (0 left, not unlimited)
        $out[] = [
            'code'      => $t['code'],
            'name'      => $t['name'],
            'color'     => $t['color'],
            'paid'      => (bool)$t['paid'],
            'total'     => $total,                       // 0 = unlimited
            'used'      => $approved,
            'pending'   => $pending,
            'remaining' => $total > 0 ? max(0, $total - $approved - $pending) : ($notYet ? 0 : null),
        ];
    }
    return $out;
}

function leaves_balance_endpoint(PDO $pdo): void {
    $employeeId = own_employee_id();
    if (is_hr() && !empty($_GET['employee_id'])) {
        $employeeId = intval($_GET['employee_id']);
    } elseif (!is_hr() && !empty($_GET['employee_id']) && is_manager_of($pdo, intval($_GET['employee_id']))) {
        $employeeId = intval($_GET['employee_id']);
    }
    if ($employeeId <= 0 || !employee_in_company($pdo, $employeeId)) {
        error_response('No employee record linked to this account', 404);
    }
    $year = !empty($_GET['year']) ? intval($_GET['year']) : (int)date('Y');
    json_response(['success' => true, 'data' => ['year' => $year, 'balances' => leaves_balance($pdo, $employeeId, $year)]]);
}

// --------------------------------------------------------------------- CRUD

function leaves_list(PDO $pdo): void {
    $where  = ['l.company_id = ?'];
    $params = [cid()];

    if (!is_hr()) {
        if (($_GET['scope'] ?? '') === 'team') {
            // A team lead sees the requests of their direct reports
            $where[]  = 'e.manager_id = ?';
            $params[] = own_employee_id();
        } else {
            $where[]  = 'l.employee_id = ?';
            $params[] = own_employee_id();
        }
    } elseif (!empty($_GET['employee_id'])) {
        $where[]  = 'l.employee_id = ?';
        $params[] = intval($_GET['employee_id']);
    }

    if (!empty($_GET['status'])) { $where[] = 'l.status = ?';                $params[] = $_GET['status']; }
    if (!empty($_GET['type']))   { $where[] = 'l.type = ?';                  $params[] = $_GET['type']; }
    if (!empty($_GET['year']))   { $where[] = 'YEAR(l.start_date) = ?';      $params[] = intval($_GET['year']); }
    if (!empty($_GET['month']))  { $where[] = 'MONTH(l.start_date) = ?';     $params[] = intval($_GET['month']); }

    $stmt = $pdo->prepare(leaves_select() . " WHERE " . implode(' AND ', $where) . " ORDER BY l.created_at DESC, l.id DESC");
    $stmt->execute($params);
    json_response(['success' => true, 'data' => $stmt->fetchAll()]);
}

function leaves_get_one(int $id, PDO $pdo, bool $respond = false): ?array {
    $leave = leaves_fetch($id, $pdo);
    if (!$leave) {
        error_response('Leave not found', 404);
    }
    if (!is_hr() && (int)$leave['employee_id'] !== own_employee_id() && !is_manager_of($pdo, (int)$leave['employee_id'])) {
        error_response('Forbidden. Insufficient permissions.', 403);
    }
    if ($respond) {
        json_response(['success' => true, 'data' => $leave]);
    }
    return $leave;
}

function leaves_create(array $body, PDO $pdo): void {
    $employeeId = intval($body['employee_id'] ?? 0);
    $type       = trim($body['type'] ?? '');
    $reason     = $body['reason'] ?? null;

    if (!is_hr()) {
        $employeeId = own_employee_id();           // employees can only request for themselves
    }
    if (!$employeeId || $type === '' || empty($body['start_date']) || empty($body['end_date'])) {
        error_response('employee_id, type, start_date, and end_date are required');
    }
    if (!employee_in_company($pdo, $employeeId)) {
        error_response('Employee not found', 404);
    }

    $start = leaves_date($body['start_date']);
    $end   = leaves_date($body['end_date']);
    if (!$start || !$end) error_response('Dates must be in YYYY-MM-DD format', 422);
    if ($end < $start)    error_response('End date must be on or after the start date', 422);
    if ($start->format('Y') !== $end->format('Y')) error_response('A request cannot span two calendar years. Please split it.', 422);

    // Leave type must exist and be active in this company
    $tStmt = $pdo->prepare("SELECT * FROM leave_types WHERE company_id = ? AND code = ? AND is_active = 1");
    $tStmt->execute([cid(), $type]);
    $lt = $tStmt->fetch();
    if (!$lt) error_response('Unknown leave type', 422);

    $days = leaves_working_days($pdo, $start, $end);
    if ($days < 1) error_response('The selected dates contain no working days (weekends and holidays are not counted)', 422);

    // No overlapping requests
    $ov = $pdo->prepare(
        "SELECT 1 FROM leaves
         WHERE company_id = ? AND employee_id = ? AND status IN ('pending','approved')
           AND start_date <= ? AND end_date >= ? LIMIT 1"
    );
    $ov->execute([cid(), $employeeId, $end->format('Y-m-d'), $start->format('Y-m-d')]);
    if ($ov->fetchColumn()) error_response('You already have a leave request in these dates', 409);

    // Balance
    $year = (int)$start->format('Y');
    if ((int)$lt['days_per_year'] > 0) {
        foreach (leaves_balance($pdo, $employeeId, $year) as $b) {
            if ($b['code'] === $type && $b['remaining'] !== null && $days > $b['remaining']) {
                error_response("Not enough {$lt['name']} balance. Remaining: {$b['remaining']} day(s), requested: $days.", 422);
            }
        }
    }

    // HR may record an already-approved leave on behalf of an employee
    $status = (is_hr() && ($body['status'] ?? '') === 'approved') ? 'approved' : 'pending';

    // Two-step approvals (feature approval_chain): the team head decides first, then HR
    $headStatus = $status === 'pending' && function_exists('chain_start_status') ? chain_start_status($pdo, $employeeId) : null;
    $pdo->prepare(
        "INSERT INTO leaves (company_id, employee_id, type, start_date, end_date, days, reason, status, head_status, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())"
    )->execute([cid(), $employeeId, $type, $start->format('Y-m-d'), $end->format('Y-m-d'), $days, $reason, $status, $headStatus]);
    $newId = (int)$pdo->lastInsertId();

    if ($status === 'pending') {
        $who = $pdo->prepare("SELECT CONCAT(first_name, ' ', last_name) FROM employees WHERE id = ?");
        $who->execute([$employeeId]);
        $name = (string)$who->fetchColumn();
        $msg  = "$name requested $days day(s) of {$lt['name']} ({$start->format('M j')} – {$end->format('M j')}).";
        notify_manager_of($pdo, $employeeId, 'leave_request', 'New leave request', $msg, ['leave_id' => $newId]);
        if ($headStatus === null) notify_hr($pdo, 'leave_request', 'New leave request', $msg, ['leave_id' => $newId], (int)me()['id']);   // with a head step HR hears of it after the head approved
    } else {
        notify_employee($pdo, $employeeId, 'leave_approved', 'Leave recorded', "Your {$lt['name']} ({$start->format('M j')} – {$end->format('M j')}) was recorded by HR.", ['leave_id' => $newId]);
    }

    json_response(['success' => true, 'data' => leaves_fetch($newId, $pdo)], 201);
}

function leaves_update(int $id, array $body, PDO $pdo): void {
    $leave = leaves_get_one($id, $pdo);
    $employeeId = (int)$leave['employee_id'];
    $isOwner    = $employeeId === own_employee_id();
    $canReview  = can_review_for($pdo, $employeeId) && !($isOwner && !is_hr());

    // Decision: approve / reject
    if (isset($body['status']) && $body['status'] !== $leave['status']) {
        $new = $body['status'];
        if (!in_array($new, ['approved', 'rejected', 'cancelled', 'pending'], true)) error_response('Invalid status', 422);
        if ($new === 'cancelled') {
            if (!$isOwner && !is_hr()) error_response('Forbidden. Insufficient permissions.', 403);
        } else {
            if (!$canReview) error_response('Forbidden. Only HR or the direct manager can review this request.', 403);
        }
        if ($leave['status'] !== 'pending' && !is_hr()) {
            error_response('This request has already been reviewed.', 409);
        }

        if (function_exists('chain_gate') && chain_gate($pdo, 'leaves', $leave, $new, $body, 'leave request') === 'head_approved') {
            audit($pdo, 'head_approved', 'leave', $id, ['employee_id' => $employeeId]);
            json_response(['success' => true, 'data' => leaves_fetch($id, $pdo)]);
        }
        if (function_exists('decision_require_reason')) decision_require_reason($pdo, $new, $body['review_note'] ?? null);   // feature fair_decisions
        $pdo->prepare(
            "UPDATE leaves SET status = ?, reviewed_by = ?, reviewed_at = NOW(), review_note = ? WHERE id = ? AND company_id = ?"
        )->execute([$new, (int)me()['id'], $body['review_note'] ?? null, $id, cid()]);

        $label = ['approved' => 'approved', 'rejected' => 'rejected', 'cancelled' => 'cancelled', 'pending' => 'reopened'][$new];
        if ($new !== 'cancelled' && !$isOwner) {
            $note = !empty($body['review_note']) ? ' Note: ' . $body['review_note'] : '';
            notify_employee($pdo, $employeeId, 'leave_' . $new, 'Leave request ' . $label,
                "Your {$leave['type_name']} request ({$leave['start_date']} – {$leave['end_date']}) was $label.$note", ['leave_id' => $id]);
        }
    }

    // Edits (dates/type/reason) only while pending, by the owner or HR
    $edits = array_intersect_key($body, array_flip(['type', 'start_date', 'end_date', 'reason']));
    if ($edits) {
        if ($leave['status'] !== 'pending') error_response('Only pending requests can be edited', 409);
        if (!$isOwner && !is_hr()) error_response('Forbidden. Insufficient permissions.', 403);

        $type  = $edits['type'] ?? $leave['type'];
        $start = leaves_date($edits['start_date'] ?? $leave['start_date']);
        $end   = leaves_date($edits['end_date'] ?? $leave['end_date']);
        if (!$start || !$end || $end < $start) error_response('Invalid dates', 422);
        $tStmt = $pdo->prepare("SELECT 1 FROM leave_types WHERE company_id = ? AND code = ? AND is_active = 1");
        $tStmt->execute([cid(), $type]);
        if (!$tStmt->fetchColumn()) error_response('Unknown leave type', 422);
        $days = leaves_working_days($pdo, $start, $end);
        if ($days < 1) error_response('The selected dates contain no working days', 422);

        $pdo->prepare(
            "UPDATE leaves SET type = ?, start_date = ?, end_date = ?, days = ?, reason = ? WHERE id = ? AND company_id = ?"
        )->execute([$type, $start->format('Y-m-d'), $end->format('Y-m-d'), $days, $edits['reason'] ?? $leave['reason'], $id, cid()]);
    }

    if (!isset($body['status']) && !$edits) {
        error_response('No fields to update');
    }
    json_response(['success' => true, 'data' => leaves_fetch($id, $pdo)]);
}

function leaves_delete(int $id, PDO $pdo): void {
    $leave = leaves_get_one($id, $pdo);
    $isOwner = (int)$leave['employee_id'] === own_employee_id();

    if (is_hr()) {
        $pdo->prepare("DELETE FROM leaves WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
        json_response(['success' => true, 'message' => 'Leave deleted']);
    }
    if ($isOwner && $leave['status'] === 'pending') {
        $pdo->prepare("UPDATE leaves SET status = 'cancelled' WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
        json_response(['success' => true, 'message' => 'Leave request cancelled']);
    }
    error_response('Only pending requests can be cancelled', 409);
}

// ------------------------------------------------------------ policy / reports

function leaves_get_policy(PDO $pdo): void {
    $stmt = $pdo->prepare("SELECT * FROM leave_policy WHERE company_id = ? LIMIT 1");
    $stmt->execute([cid()]);
    $policy = $stmt->fetch();
    json_response(['success' => true, 'data' => $policy ?: ['days_per_month' => 2, 'days_per_year' => 21]]);
}

function leaves_update_policy(array $body, PDO $pdo): void {
    $stmt = $pdo->prepare("SELECT id FROM leave_policy WHERE company_id = ? LIMIT 1");
    $stmt->execute([cid()]);
    $existing = $stmt->fetch();

    $dpm = isset($body['days_per_month']) ? intval($body['days_per_month']) : null;
    $dpy = isset($body['days_per_year'])  ? intval($body['days_per_year'])  : null;

    if ($existing) {
        $fields = [];
        $params = [];
        if ($dpm !== null) { $fields[] = 'days_per_month = ?'; $params[] = $dpm; }
        if ($dpy !== null) { $fields[] = 'days_per_year = ?';  $params[] = $dpy; }
        if (!empty($fields)) {
            $params[] = $existing['id'];
            $params[] = cid();
            $pdo->prepare("UPDATE leave_policy SET " . implode(', ', $fields) . " WHERE id = ? AND company_id = ?")->execute($params);
        }
    } else {
        $pdo->prepare("INSERT INTO leave_policy (company_id, days_per_month, days_per_year) VALUES (?, ?, ?)")
            ->execute([cid(), $dpm ?? 2, $dpy ?? 21]);
    }

    leaves_get_policy($pdo);
}

function leaves_policy_values(PDO $pdo): array {
    $p = $pdo->prepare("SELECT days_per_month, days_per_year FROM leave_policy WHERE company_id = ? LIMIT 1");
    $p->execute([cid()]);
    $r = $p->fetch();
    return [(int)($r['days_per_month'] ?? 2), (int)($r['days_per_year'] ?? 21)];
}

/** Approved leave days taken by an employee: [this week, this month, this year]. */
function leaves_taken(PDO $pdo, int $employeeId, DateTime $now): array {
    $week  = (clone $now)->modify('monday this week')->format('Y-m-d');
    $month = $now->format('Y-m-01');
    $year  = $now->format('Y-01-01');
    $s = $pdo->prepare(
        "SELECT COALESCE(SUM(CASE WHEN start_date >= ? THEN days END), 0) AS w,
                COALESCE(SUM(CASE WHEN start_date >= ? THEN days END), 0) AS m,
                COALESCE(SUM(CASE WHEN start_date >= ? THEN days END), 0) AS y
         FROM leaves WHERE company_id = ? AND employee_id = ? AND status = 'approved' AND start_date >= ? AND start_date <= ?"
    );
    $s->execute([$week, $month, $year, cid(), $employeeId, $year, $now->format('Y-12-31')]);
    $r = $s->fetch();
    return [(int)$r['w'], (int)$r['m'], (int)$r['y']];
}

function leaves_analytics(PDO $pdo): void {
    $now = new DateTime('now', new DateTimeZone(company_get($pdo, cid())['timezone'] ?? 'UTC'));
    [$perMonth, $perYear] = leaves_policy_values($pdo);
    $emps = $pdo->prepare("SELECT id, first_name, last_name, position, department_id, status FROM employees WHERE company_id = ? AND status != 'inactive' ORDER BY first_name, last_name");
    $emps->execute([cid()]);
    $pending = $pdo->prepare("SELECT COUNT(*) FROM leaves WHERE company_id = ? AND employee_id = ? AND status = 'pending'");
    $out = [];
    foreach ($emps->fetchAll() as $e) {
        [$w, $m, $y] = leaves_taken($pdo, (int)$e['id'], $now);
        $pending->execute([cid(), $e['id']]);
        $out[] = [
            'employee_id' => (int)$e['id'], 'first_name' => $e['first_name'], 'last_name' => $e['last_name'], 'position' => $e['position'] ?? '',
            'department_id' => $e['department_id'] === null ? 0 : (int)$e['department_id'], 'status' => $e['status'],
            'taken_this_week' => $w, 'taken_this_month' => $m, 'taken_this_year' => $y,
            'remaining_this_month' => max(0, $perMonth - $m), 'remaining_this_year' => max(0, $perYear - $y),
            'pending_requests' => (int)$pending->fetchColumn(),
        ];
    }
    json_response(['success' => true, 'data' => $out]);
}

function leaves_analytics_employee(int $employeeId, PDO $pdo): void {
    $es = $pdo->prepare("SELECT id, first_name, last_name, position, department_id, status FROM employees WHERE id = ? AND company_id = ?");
    $es->execute([$employeeId, cid()]);
    $e = $es->fetch();
    if (!$e) error_response('Employee not found', 404);

    $now = new DateTime('now', new DateTimeZone(company_get($pdo, cid())['timezone'] ?? 'UTC'));
    [$perMonth, $perYear] = leaves_policy_values($pdo);
    [$w, $m, $y] = leaves_taken($pdo, $employeeId, $now);

    $h = $pdo->prepare("SELECT id, type, start_date, end_date, days, reason, status, created_at FROM leaves WHERE employee_id = ? AND company_id = ? ORDER BY start_date DESC");
    $h->execute([$employeeId, cid()]);
    $history = $h->fetchAll();
    $pending = count(array_filter($history, fn($l) => $l['status'] === 'pending'));
    $totalAll = array_sum(array_map(fn($l) => $l['status'] === 'approved' ? (int)$l['days'] : 0, $history));

    json_response(['success' => true, 'data' => [
        'employee' => ['id' => (int)$e['id'], 'first_name' => $e['first_name'], 'last_name' => $e['last_name'], 'position' => $e['position'] ?? '',
                       'department_id' => $e['department_id'] === null ? 0 : (int)$e['department_id'], 'status' => $e['status']],
        'policy'   => ['days_per_month' => $perMonth, 'days_per_year' => $perYear],
        'summary'  => ['taken_this_week' => $w, 'taken_this_month' => $m, 'taken_this_year' => $y,
                       'remaining_this_month' => max(0, $perMonth - $m), 'remaining_this_year' => max(0, $perYear - $y),
                       'pending_requests' => $pending, 'total_all' => $totalAll],
        'history'  => $history,
    ]]);
}
