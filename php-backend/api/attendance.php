<?php
/**
 * Attendance API handler (company-scoped)
 *
 * Status (present / late / half_day / absent) is ALWAYS derived by the server from the shift,
 * the company policy, the time of each action and the time spent outside the work zone.
 * Employees cannot choose or edit it; they can only ask HR through a request.
 *
 *   GET  /attendance                 list  (filters: employee_id, date, from, to, month, year, status)
 *   GET  /attendance/today           caller's day: record, shift, rule(s), policy, holiday / leave flags
 *   GET  /attendance/summary         monthly summary (HR: ?employee_id=)
 *   GET  /attendance/board           live board for a date (HR)
 *   POST /attendance/check-in        {lat,lng,ssid,bssid}
 *   POST /attendance/ping            {lat,lng,ssid,bssid}  location heartbeat while checked in
 *   POST /attendance/check-out       {lat,lng,ssid,bssid}
 *   POST /attendance                 manual record (HR)
 *   PUT/DELETE /attendance/{id}      edit / delete (HR)
 */
require_once __DIR__ . '/attendance_rules.php';
require_once __DIR__ . '/../helpers/policy.php';
require_once __DIR__ . '/../helpers/attendance_trust.php';

function handle_attendance(string $path, string $method, array $body): void {
    $pdo      = getDB();
    $segments = explode('/', $path);
    $sub      = $segments[1] ?? '';

    switch ($sub) {
        case 'today':     if ($method !== 'GET')  error_response('Method not allowed', 405); attendance_today($pdo);    return;
        case 'summary':   if ($method !== 'GET')  error_response('Method not allowed', 405); attendance_summary($pdo);  return;
        case 'board':     if ($method !== 'GET')  error_response('Method not allowed', 405); require_hr(); attendance_board($pdo); return;
        case 'check-in':  if ($method !== 'POST') error_response('Method not allowed', 405); attendance_check_in($body, $pdo);  return;
        case 'check-out': if ($method !== 'POST') error_response('Method not allowed', 405); attendance_check_out($body, $pdo); return;
        case 'ping':      if ($method !== 'POST') error_response('Method not allowed', 405); attendance_ping($body, $pdo);      return;
        case 'explain':   if ($method !== 'GET')  error_response('Method not allowed', 405); attendance_explain_endpoint($pdo); return;
    }

    $id = ($sub !== '' && is_numeric($sub)) ? intval($sub) : null;

    if ($id !== null) {
        switch ($method) {
            case 'GET':    attendance_get_one($id, $pdo); break;
            case 'PUT':    require_hr(); attendance_update($id, $body, $pdo); break;
            case 'DELETE': require_hr(); attendance_delete($id, $pdo); break;
            default:       error_response('Method not allowed', 405);
        }
    } else {
        switch ($method) {
            case 'GET':  attendance_list($pdo); break;
            case 'POST': require_hr(); attendance_create($body, $pdo); break;
            default:     error_response('Method not allowed', 405);
        }
    }
}

// ------------------------------------------------------------------ helpers

function attendance_now(PDO $pdo): DateTime { return att_now($pdo); }

function attendance_employee_row(PDO $pdo, int $employeeId): ?array { return att_employee_row($pdo, $employeeId); }

function attendance_holiday(PDO $pdo, string $date): ?string {
    $s = $pdo->prepare("SELECT name FROM holidays WHERE company_id = ? AND date = ?");
    $s->execute([cid(), $date]);
    $n = $s->fetchColumn();
    return $n === false ? null : (string)$n;
}

function attendance_on_leave(PDO $pdo, int $employeeId, string $date): ?array {
    $s = $pdo->prepare(
        "SELECT l.id, l.type, lt.name AS type_name FROM leaves l
         LEFT JOIN leave_types lt ON lt.company_id = l.company_id AND lt.code = l.type
         WHERE l.company_id = ? AND l.employee_id = ? AND l.status = 'approved' AND l.start_date <= ? AND l.end_date >= ? LIMIT 1"
    );
    $s->execute([cid(), $employeeId, $date, $date]);
    return $s->fetch() ?: null;
}

function attendance_select(): string {
    return "SELECT a.*,
                   CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
                   e.avatar AS employee_avatar,
                   e.department_id,
                   d.name AS department_name
            FROM attendance a
            JOIN employees e ON e.id = a.employee_id
            LEFT JOIN departments d ON d.id = e.department_id";
}

function attendance_fetch(int $id, PDO $pdo): ?array {
    $stmt = $pdo->prepare(attendance_select() . " WHERE a.id = ? AND a.company_id = ?");
    $stmt->execute([$id, cid()]);
    return $stmt->fetch() ?: null;
}

/** An employee's still-open record (today's, or yesterday's for a shift that ran past midnight). */
function attendance_open_record(PDO $pdo, int $employeeId, DateTime $now): ?array {
    att_close_stale($pdo, $employeeId);
    $s = $pdo->prepare(
        "SELECT * FROM attendance WHERE company_id = ? AND employee_id = ? AND check_out IS NULL AND closed = 0 AND date >= ?
         ORDER BY date DESC, id DESC LIMIT 1"
    );
    $s->execute([cid(), $employeeId, (clone $now)->modify('-1 day')->format('Y-m-d')]);
    return $s->fetch() ?: null;
}

function attendance_coord($body, string $k): ?float {
    return isset($body[$k]) && is_numeric($body[$k]) ? (float)$body[$k] : null;
}

/**
 * What the board / reports show for a day.
 *  present | late | half_day | absent      -> from the attendance record
 *  on_leave | holiday | off                 -> not a working day for this person
 *  not_in                                   -> today, nobody has checked in yet
 */
function attendance_day_status(PDO $pdo, array $emp, string $date, DateTime $now, ?array $rec, ?array $leave, ?string $holiday): string {
    if ($rec) return $rec['status'];
    if ($leave) return 'on_leave';
    if ($holiday) return 'holiday';
    $shift = att_shift($pdo, $emp);
    if (!att_is_workday($pdo, $shift, $date)) return 'off';
    $today = $now->format('Y-m-d');
    if ($date > $today) return 'off';
    if ($date < $today) return 'absent';
    $end = new DateTime($date . ' ' . $shift['end'], $now->getTimezone());
    if (att_min($shift['end']) <= att_min($shift['start'])) $end->modify('+1 day');
    return $now >= $end ? 'absent' : 'not_in';
}

// ------------------------------------------------------------------- reads

function attendance_list(PDO $pdo): void {
    att_close_stale($pdo, is_hr() ? null : own_employee_id());
    $where  = ['a.company_id = ?'];
    $params = [cid()];

    if (!is_hr()) {                       // defence in depth: employees only ever see their own
        $where[]  = 'a.employee_id = ?';
        $params[] = own_employee_id();
    } elseif (!empty($_GET['employee_id'])) {
        $where[]  = 'a.employee_id = ?';
        $params[] = intval($_GET['employee_id']);
    }
    if (!empty($_GET['date']))  { $where[] = 'a.date = ?';          $params[] = $_GET['date']; }
    if (!empty($_GET['from']))  { $where[] = 'a.date >= ?';         $params[] = $_GET['from']; }
    if (!empty($_GET['to']))    { $where[] = 'a.date <= ?';         $params[] = $_GET['to']; }
    if (!empty($_GET['month'])) { $where[] = 'MONTH(a.date) = ?';   $params[] = intval($_GET['month']); }
    if (!empty($_GET['year']))  { $where[] = 'YEAR(a.date) = ?';    $params[] = intval($_GET['year']); }
    if (!empty($_GET['status'])){ $where[] = 'a.status = ?';        $params[] = $_GET['status']; }

    $limit = isset($_GET['limit']) ? max(1, min(500, intval($_GET['limit']))) : 300;

    $stmt = $pdo->prepare(attendance_select() . " WHERE " . implode(' AND ', $where) . " ORDER BY a.date DESC, a.check_in DESC LIMIT $limit");
    $stmt->execute($params);
    json_response(['success' => true, 'data' => $stmt->fetchAll()]);
}

function attendance_get_one(int $id, PDO $pdo): void {
    $record = attendance_fetch($id, $pdo);
    if (!$record) {
        error_response('Attendance record not found', 404);
    }
    json_response(['success' => true, 'data' => $record]);
}

/** Rules as the apps show them: one merged summary plus the individual rules. */
function attendance_rules_summary(PDO $pdo): ?array {
    $rules = att_active_rules($pdo);
    if (!$rules) return null;
    $loc = array_values(array_filter($rules, fn($r) => (int)$r['location_enabled'] === 1));
    $wifi = array_values(array_filter($rules, fn($r) => (int)$r['wifi_enabled'] === 1 && !empty($r['wifi_ssid'])));
    return [
        'name' => implode(', ', array_map(fn($r) => $r['name'], $rules)),
        'location_enabled' => count($loc) > 0, 'wifi_enabled' => count($wifi) > 0,
        'wifi_ssid' => implode(', ', array_unique(array_map(fn($r) => $r['wifi_ssid'], $wifi))) ?: null,
        'radius_m' => $loc ? min(array_map(fn($r) => (float)$r['location_radius_km'] * 1000, $loc)) : null,
        'match_mode' => $rules[0]['match_mode'] ?? 'any',
        'count' => count($rules),
    ];
}

/** The mobile home screen: everything needed to render today's attendance card. */
function attendance_today(PDO $pdo): void {
    $employeeId = own_employee_id();
    $emp = $employeeId > 0 ? att_employee_row($pdo, $employeeId) : null;
    if (!$emp) error_response('No employee record linked to this account', 404);

    $now   = att_now($pdo);
    $today = $now->format('Y-m-d');
    att_close_stale($pdo, $employeeId);

    $r = $pdo->prepare(attendance_select() . " WHERE a.company_id = ? AND a.employee_id = ? AND a.date = ? ORDER BY a.id DESC LIMIT 1");
    $r->execute([cid(), $employeeId, $today]);
    $record = $r->fetch() ?: null;
    if (!$record) {                                        // shift that ran past midnight: still open from yesterday
        $open = attendance_open_record($pdo, $employeeId, $now);
        if ($open) { $record = attendance_fetch((int)$open['id'], $pdo); }
    }

    $company = company_get($pdo, cid());
    $shift   = att_shift($pdo, $emp);
    $holiday = attendance_holiday($pdo, $today);
    $leave   = attendance_on_leave($pdo, $employeeId, $today);
    $isWorkday = att_is_workday($pdo, $shift, $today);
    $policy  = att_policy($pdo);

    $state = 'ready';                                       // ready | checked_in | checked_out
    if ($record && $record['check_out']) $state = 'checked_out';
    elseif ($record)                    $state = 'checked_in';

    json_response(['success' => true, 'data' => [
        'date'        => $today,
        'server_time' => $now->format('c'),
        'timezone'    => $company['timezone'],
        'state'       => $state,
        'record'      => $record,
        'shift'       => ['name' => $shift['name'], 'start_time' => $shift['start'], 'end_time' => $shift['end'], 'days' => $shift['days'], 'is_default' => $shift['default']],
        'rule'        => attendance_rules_summary($pdo),
        'policy'      => [
            'track_location' => (bool)$policy['track_location'], 'ping_interval_minutes' => (int)$policy['ping_interval_minutes'],
            'out_zone_half_day_minutes' => (int)$policy['out_zone_half_day_minutes'], 'late_grace_minutes' => (int)$company['late_grace_minutes'],
            'half_day_late_minutes' => (int)$policy['half_day_late_minutes'],
        ],
        'holiday'     => $holiday,
        'on_leave'    => $leave,
        'is_weekend'  => !$isWorkday && !$holiday,
        'is_workday'  => $isWorkday && !$holiday && !$leave,
    ]]);
}

function attendance_summary(PDO $pdo): void {
    $employeeId = own_employee_id();
    if (is_hr() && !empty($_GET['employee_id'])) $employeeId = intval($_GET['employee_id']);
    if ($employeeId <= 0 || !employee_in_company($pdo, $employeeId)) error_response('No employee record linked to this account', 404);
    att_close_stale($pdo, $employeeId);

    $now   = att_now($pdo);
    $month = !empty($_GET['month']) ? max(1, min(12, intval($_GET['month']))) : (int)$now->format('n');
    $year  = !empty($_GET['year'])  ? intval($_GET['year']) : (int)$now->format('Y');

    $s = $pdo->prepare(
        "SELECT * FROM attendance WHERE company_id = ? AND employee_id = ? AND MONTH(date) = ? AND YEAR(date) = ? ORDER BY date"
    );
    $s->execute([cid(), $employeeId, $month, $year]);
    $rows = $s->fetchAll();
    $byDate = [];
    foreach ($rows as $r) $byDate[$r['date']] = $r;

    $present = $late = $half = $absent = $early = 0;
    $hours = 0.0; $lateMinutes = 0; $overtime = 0; $outZone = 0;
    foreach ($rows as $r) {
        if     ($r['status'] === 'present')  $present++;
        elseif ($r['status'] === 'late')     { $late++; $lateMinutes += (int)$r['late_minutes']; }
        elseif ($r['status'] === 'half_day') $half++;
        elseif ($r['status'] === 'absent')   $absent++;
        if ((int)$r['early_leave_minutes'] > 0) $early++;
        $hours += (float)$r['hours_worked'];
        $overtime += (int)$r['overtime_minutes'];
        $outZone  += (int)$r['out_zone_minutes'];
    }

    // Working days with no record at all count as absent (only days that are over)
    $emp = att_employee_row($pdo, $employeeId);
    $first = new DateTime(sprintf('%04d-%02d-01', $year, $month));
    $last  = (clone $first)->modify('last day of this month');
    $days = [];
    for ($d = clone $first; $d <= $last; $d->modify('+1 day')) {
        $ds = $d->format('Y-m-d');
        if (isset($byDate[$ds])) { $days[$ds] = $byDate[$ds]['status']; continue; }
        if ($ds > $now->format('Y-m-d')) continue;
        $st = attendance_day_status($pdo, $emp, $ds, $now, null, attendance_on_leave($pdo, $employeeId, $ds), attendance_holiday($pdo, $ds));
        if ($st === 'absent') { $absent++; }
        if ($st !== 'not_in') $days[$ds] = $st;
    }

    $lv = $pdo->prepare(
        "SELECT COALESCE(SUM(days), 0) FROM leaves WHERE company_id = ? AND employee_id = ? AND status = 'approved'
           AND MONTH(start_date) = ? AND YEAR(start_date) = ?"
    );
    $lv->execute([cid(), $employeeId, $month, $year]);

    json_response(['success' => true, 'data' => [
        'month' => $month, 'year' => $year,
        'present_days' => $present, 'late_days' => $late, 'half_days' => $half, 'absent_days' => $absent,
        'leave_days'   => (int)$lv->fetchColumn(),
        'total_hours'  => round($hours, 2),
        'late_minutes' => $lateMinutes, 'early_leave_days' => $early,
        'overtime_minutes' => $overtime, 'out_zone_minutes' => $outZone,
        'days'         => $days,
        'records'      => $rows,
    ]]);
}

/** HR live board: every active employee with the day's status. */
function attendance_board(PDO $pdo): void {
    att_close_stale($pdo);
    $now  = att_now($pdo);
    $date = !empty($_GET['date']) ? $_GET['date'] : $now->format('Y-m-d');

    $s = $pdo->prepare(
        "SELECT e.*, d.name AS department_name, s.name AS shift_name, s.start_time AS shift_start, s.end_time AS shift_end, s.days AS shift_days,
                a.id AS attendance_id, a.check_in, a.check_out, a.status AS att_status, a.late_minutes, a.hours_worked, a.flags,
                a.out_zone_minutes, a.last_ping_inside, a.last_ping_at, a.early_leave_minutes, a.overtime_minutes, a.closed, a.security_flags
         FROM employees e
         LEFT JOIN departments d ON d.id = e.department_id
         LEFT JOIN shifts s ON s.id = e.shift_id
         LEFT JOIN attendance a ON a.employee_id = e.id AND a.date = ? AND a.company_id = e.company_id
         WHERE e.company_id = ? AND e.status != 'inactive'
         ORDER BY e.first_name, e.last_name"
    );
    $s->execute([$date, cid()]);
    $rows = $s->fetchAll();
    $holiday = attendance_holiday($pdo, $date);

    $counts = ['present' => 0, 'late' => 0, 'half_day' => 0, 'absent' => 0, 'on_leave' => 0, 'not_in' => 0, 'off' => 0];
    $out = [];
    foreach ($rows as $e) {
        $rec = $e['attendance_id'] ? ['status' => $e['att_status']] : null;
        $leave = attendance_on_leave($pdo, (int)$e['id'], $date);
        $st = attendance_day_status($pdo, $e, $date, $now, $rec, $leave, $holiday);
        $key = $st === 'holiday' ? 'off' : $st;
        if (isset($counts[$key])) $counts[$key]++;
        $out[] = [
            'employee_id' => (int)$e['id'], 'employee_name' => $e['first_name'] . ' ' . $e['last_name'], 'employee_avatar' => $e['avatar'],
            'position' => $e['position'], 'department_name' => $e['department_name'],
            'attendance_id' => $e['attendance_id'], 'check_in' => $e['check_in'], 'check_out' => $e['check_out'],
            'status' => $e['att_status'], 'board_status' => $st, 'late_minutes' => $e['late_minutes'], 'hours_worked' => $e['hours_worked'],
            'flags' => $e['flags'], 'out_zone_minutes' => $e['out_zone_minutes'] ?? 0, 'outside_now' => $e['last_ping_inside'] !== null && (int)$e['last_ping_inside'] === 0 && !$e['check_out'],
            'early_leave_minutes' => $e['early_leave_minutes'] ?? 0, 'overtime_minutes' => $e['overtime_minutes'] ?? 0,
            'leave_type' => $leave['type_name'] ?? null, 'security_flags' => $e['security_flags'] ?? null,
        ];
    }
    json_response(['success' => true, 'data' => [
        'date' => $date, 'holiday' => $holiday, 'counts' => $counts,
        'total' => count($out), 'employees' => $out,
    ]]);
}

// ---------------------------------------------------------- mobile check-in / ping / out

function attendance_check_in(array $body, PDO $pdo): void {
    $employeeId = own_employee_id();
    $emp = $employeeId > 0 ? att_employee_row($pdo, $employeeId) : null;
    if (!$emp) error_response('No employee record linked to this account', 404);
    if ($emp['status'] === 'inactive') error_response('Your employee account is inactive', 403);

    $trust = attendance_prepare($body, $pdo, 'check_in', $employeeId);     // fake GPS, shared phone, offline sync
    $now   = att_now($pdo);
    $today = $now->format('Y-m-d');

    if (attendance_on_leave($pdo, $employeeId, $today)) error_response('You are on approved leave today.', 422);

    $ex = $pdo->prepare("SELECT id FROM attendance WHERE company_id = ? AND employee_id = ? AND date = ? LIMIT 1");
    $ex->execute([cid(), $employeeId, $today]);
    if ($ex->fetchColumn()) error_response('You have already checked in today.', 409);
    if (attendance_open_record($pdo, $employeeId, $now)) error_response('You are still checked in from yesterday. Please check out first.', 409);

    $zone = att_zone($pdo, $body);
    if ($zone['constrained'] && !$zone['inside']) error_response($zone['message'], 422);

    $pdo->prepare(
        "INSERT INTO attendance (company_id, employee_id, date, check_in, status, source, check_in_lat, check_in_lng, check_in_inside,
                                 last_ping_at, last_inside_at, last_ping_inside, note)
         VALUES (?, ?, ?, ?, 'present', 'mobile', ?, ?, ?, ?, ?, ?, ?)"
    )->execute([
        cid(), $employeeId, $today, $now->format('H:i:s'),
        attendance_coord($body, 'lat'), attendance_coord($body, 'lng'),
        $zone['constrained'] ? 1 : null, $now->format('Y-m-d H:i:s'), $now->format('Y-m-d H:i:s'), $zone['constrained'] ? 1 : null,
        isset($body['note']) ? mb_substr((string)$body['note'], 0, 500) : null,
    ]);
    $id = (int)$pdo->lastInsertId();
    attendance_save_security($pdo, $id, $trust);
    $rec = attendance_fetch($id, $pdo);

    $shift = att_shift($pdo, $emp);
    if (!att_is_workday($pdo, $shift, $today) || attendance_holiday($pdo, $today)) {
        // Working on a day off: never late, flagged so payroll/reports can treat it as extra work
        $pdo->prepare("UPDATE attendance SET status = 'present', flags = 'day_off_work' WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
    } else {
        $ev = att_apply($pdo, $rec, $emp);
        if ($ev['status'] !== 'present') {
            $name = $emp['first_name'] . ' ' . $emp['last_name'];
            $label = $ev['status'] === 'half_day' ? 'half-day check-in' : ($ev['status'] === 'absent' ? 'very late check-in' : 'late check-in');
            notify_manager_of($pdo, $employeeId, 'late_checkin', ucfirst($label), "$name: {$ev['late_minutes']} min after shift start.", ['employee_id' => $employeeId]);
        }
    }
    json_response(['success' => true, 'data' => attendance_fetch($id, $pdo)], 201);
}

/** Location heartbeat: the app calls this every few minutes while the employee is checked in. */
function attendance_ping(array $body, PDO $pdo): void {
    $employeeId = own_employee_id();
    if ($employeeId <= 0 || !employee_in_company($pdo, $employeeId)) error_response('No employee record linked to this account', 404);
    $trust = attendance_prepare($body, $pdo, 'ping', $employeeId);
    $now = att_now($pdo);
    $rec = attendance_open_record($pdo, $employeeId, $now);
    if (!$rec) json_response(['success' => true, 'data' => ['state' => 'none']]);
    attendance_save_security($pdo, (int)$rec['id'], $trust);

    $p    = att_policy($pdo);
    $zone = att_zone($pdo, $body);
    $stamp = $now->format('Y-m-d H:i:s');
    $out  = (int)$rec['out_zone_minutes'];
    $before = $out;

    if ($zone['constrained']) {
        $last = $rec['last_ping_at'] ? new DateTime($rec['last_ping_at'], $now->getTimezone()) : new DateTime($rec['date'] . ' ' . $rec['check_in'], $now->getTimezone());
        $gap  = max(0, (int)floor(($now->getTimestamp() - $last->getTimestamp()) / 60));
        if (!$zone['inside']) $out += min($gap, (int)$p['max_ping_gap_minutes']);
        $pdo->prepare(
            "UPDATE attendance SET last_ping_at = ?, last_ping_inside = ?, last_inside_at = IF(?, ?, last_inside_at), out_zone_minutes = ? WHERE id = ? AND company_id = ?"
        )->execute([$stamp, $zone['inside'] ? 1 : 0, $zone['inside'] ? 1 : 0, $stamp, $out, $rec['id'], cid()]);
        $rec['out_zone_minutes'] = $out;
        $ev = att_apply($pdo, $rec);

        $limit = (int)$p['out_zone_half_day_minutes'];
        if ($limit > 0 && $before < $limit && $out >= $limit) {
            $emp = att_employee_row($pdo, $employeeId);
            $name = $emp['first_name'] . ' ' . $emp['last_name'];
            notify_employee($pdo, $employeeId, 'left_zone', 'You left the workplace',
                "You have been away from the workplace for $out minutes, so today counts as a half day.", ['attendance_id' => (int)$rec['id']]);
            notify_hr($pdo, 'left_zone', 'Employee away from workplace', "$name has been outside the work zone for $out minutes (half day).", ['employee_id' => $employeeId]);
        }
    } else {
        $ev = ['status' => $rec['status']];
    }
    json_response(['success' => true, 'data' => [
        'state' => 'open', 'constrained' => $zone['constrained'], 'inside' => $zone['inside'], 'message' => $zone['message'],
        'distance_m' => $zone['distance_m'] !== null ? round($zone['distance_m']) : null,
        'out_zone_minutes' => $out, 'status' => $ev['status'],
    ]]);
}

function attendance_check_out(array $body, PDO $pdo): void {
    $employeeId = own_employee_id();
    if ($employeeId <= 0 || !employee_in_company($pdo, $employeeId)) error_response('No employee record linked to this account', 404);

    $trust = attendance_prepare($body, $pdo, 'check_out', $employeeId);
    $now = att_now($pdo);
    $rec = attendance_open_record($pdo, $employeeId, $now);
    if (!$rec) error_response('You have not checked in yet.', 409);
    attendance_save_security($pdo, (int)$rec['id'], $trust);

    $p    = att_policy($pdo);
    $zone = att_zone($pdo, $body);
    if ($zone['constrained'] && !$zone['inside'] && !$p['allow_checkout_outside']) error_response($zone['message'], 422);

    $out = (int)$rec['out_zone_minutes'];
    if ($zone['constrained'] && !$zone['inside']) {
        $last = $rec['last_ping_at'] ? new DateTime($rec['last_ping_at'], $now->getTimezone()) : new DateTime($rec['date'] . ' ' . $rec['check_in'], $now->getTimezone());
        $out += min(max(0, (int)floor(($now->getTimestamp() - $last->getTimestamp()) / 60)), (int)$p['max_ping_gap_minutes']);
    }

    $pdo->prepare(
        "UPDATE attendance SET check_out = ?, closed = 1, out_zone_minutes = ?, check_out_inside = ?, check_out_lat = ?, check_out_lng = ?,
                last_ping_at = ?, last_ping_inside = ? WHERE id = ? AND company_id = ?"
    )->execute([
        $now->format('H:i:s'), $out, $zone['constrained'] ? ($zone['inside'] ? 1 : 0) : null,
        attendance_coord($body, 'lat'), attendance_coord($body, 'lng'),
        $now->format('Y-m-d H:i:s'), $zone['constrained'] ? ($zone['inside'] ? 1 : 0) : null, $rec['id'], cid(),
    ]);
    $rec['check_out'] = $now->format('H:i:s'); $rec['out_zone_minutes'] = $out; $rec['closed'] = 1;

    $emp = att_employee_row($pdo, $employeeId);
    $shift = att_shift($pdo, $emp);
    $ev = null;
    if (att_is_workday($pdo, $shift, $rec['date']) && !attendance_holiday($pdo, $rec['date'])) {
        $ev = att_apply($pdo, $rec, $emp, true);
    } else {
        $pdo->prepare("UPDATE attendance SET hours_worked = ?, flags = 'day_off_work' WHERE id = ? AND company_id = ?")
            ->execute([att_hours($rec['check_in'], $rec['check_out']), $rec['id'], cid()]);
    }

    // Today's reward (green / red / black) is settled now that the day is complete
    $reward = null;
    require_once __DIR__ . '/../helpers/points.php';
    {
        points_sync_employee($pdo, $employeeId);
        $r = $pdo->prepare("SELECT color, reason FROM points_ledger WHERE company_id = ? AND employee_id = ? AND auto_key = ? LIMIT 1");
        $r->execute([cid(), $employeeId, $rec['date']]);
        $reward = $r->fetch() ?: null;
    }
    $row = attendance_fetch((int)$rec['id'], $pdo);
    $row['reward'] = $reward;
    json_response(['success' => true, 'data' => $row]);
}

function att_hours(?string $in, ?string $out): ?float {
    if (!$in || !$out) return null;
    $h = (strtotime($out) - strtotime($in)) / 3600;
    if ($h < 0) $h += 24;
    return round($h, 2);
}

// -------------------------------------------------------------------- HR CRUD

function attendance_create(array $body, PDO $pdo): void {
    $employeeId = intval($body['employee_id'] ?? 0);
    $date       = $body['date'] ?? date('Y-m-d');
    $checkIn    = !empty($body['check_in'])  ? $body['check_in']  : null;
    $checkOut   = !empty($body['check_out']) ? $body['check_out'] : null;

    if (!$employeeId) error_response('employee_id is required');
    if (!employee_in_company($pdo, $employeeId)) error_response('Employee not found', 404);
    if (!empty($body['status']) && !in_array($body['status'], ['present', 'absent', 'half_day', 'late'], true)) error_response('Invalid status', 422);
    if (!$checkIn && empty($body['status'])) error_response('Enter a check-in time or choose a status', 422);

    $dup = $pdo->prepare("SELECT id FROM attendance WHERE company_id = ? AND employee_id = ? AND date = ? LIMIT 1");
    $dup->execute([cid(), $employeeId, $date]);
    if ($dup->fetchColumn()) error_response('There is already an attendance record for this employee on this date', 409);

    $pdo->prepare(
        "INSERT INTO attendance (company_id, employee_id, date, check_in, check_out, status, hours_worked, source, note, closed, edited_by)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'manual', ?, 1, ?)"
    )->execute([cid(), $employeeId, $date, $checkIn, $checkOut, $body['status'] ?? 'present', att_hours($checkIn, $checkOut), $body['note'] ?? null, (int)me()['id']]);
    $id = (int)$pdo->lastInsertId();
    if ($checkIn && empty($body['status'])) att_apply($pdo, attendance_fetch($id, $pdo), null, true);   // derive automatically
    points_reeval_safe($pdo, $employeeId, $date);
    audit($pdo, 'create', 'attendance', $id, ['employee_id' => $employeeId, 'date' => $date]);
    attendance_get_one($id, $pdo);
}

function points_reeval_safe(PDO $pdo, int $employeeId, string $date): void {
    require_once __DIR__ . '/../helpers/points.php';
    points_reeval($pdo, $employeeId, $date);
}

function attendance_update(int $id, array $body, PDO $pdo): void {
    $current = attendance_fetch($id, $pdo);
    if (!$current) error_response('Attendance record not found', 404);
    if (isset($body['status']) && !in_array($body['status'], ['present', 'absent', 'half_day', 'late'], true)) error_response('Invalid status', 422);

    $fields = ['edited_by = ?']; $params = [(int)me()['id']];
    foreach (['date', 'check_in', 'check_out', 'status', 'note'] as $f) {
        if (array_key_exists($f, $body)) {
            $fields[] = "$f = ?";
            $params[]  = $body[$f] === '' ? null : $body[$f];
        }
    }
    $in  = array_key_exists('check_in', $body)  ? ($body['check_in'] ?: null)  : $current['check_in'];
    $out = array_key_exists('check_out', $body) ? ($body['check_out'] ?: null) : $current['check_out'];
    if ($in && $out) { $fields[] = 'hours_worked = ?'; $params[] = att_hours($in, $out); }
    if ($out) { $fields[] = 'closed = 1'; }
    if (count($fields) === 1) error_response('No fields to update');

    $params[] = $id; $params[] = cid();
    $pdo->prepare("UPDATE attendance SET " . implode(', ', $fields) . " WHERE id = ? AND company_id = ?")->execute($params);

    // Times changed and HR did not force a status -> the server re-derives it
    if ((array_key_exists('check_in', $body) || array_key_exists('check_out', $body)) && !array_key_exists('status', $body)) {
        att_apply($pdo, attendance_fetch($id, $pdo), null, true);
    }
    points_reeval_safe($pdo, (int)$current['employee_id'], $current['date']);
    if (!empty($body['date']) && $body['date'] !== $current['date']) points_reeval_safe($pdo, (int)$current['employee_id'], $body['date']);
    audit($pdo, 'update', 'attendance', $id, $body);
    attendance_get_one($id, $pdo);
}

function attendance_delete(int $id, PDO $pdo): void {
    $rec = attendance_fetch($id, $pdo);
    if (!$rec) error_response('Attendance record not found', 404);
    $pdo->prepare("DELETE FROM attendance WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
    points_reeval_safe($pdo, (int)$rec['employee_id'], $rec['date']);
    audit($pdo, 'delete', 'attendance', $id, ['employee_id' => $rec['employee_id'], 'date' => $rec['date']]);
    json_response(['success' => true, 'message' => 'Attendance record deleted']);
}


/** GET /attendance/explain?date=YYYY-MM-DD[&employee_id=]  why a day was marked the way it was. */
function attendance_explain_endpoint(PDO $pdo): void {
    $eid = own_employee_id();
    if (!empty($_GET['employee_id'])) {
        $asked = intval($_GET['employee_id']);
        if ($asked !== $eid && !is_hr() && !is_manager_of($pdo, $asked)) error_response('Forbidden. Insufficient permissions.', 403);
        $eid = $asked;
    }
    if ($eid <= 0 || !employee_in_company($pdo, $eid)) error_response('No employee record linked to this account', 404);
    $date = (string)($_GET['date'] ?? att_now($pdo)->format('Y-m-d'));
    $d = DateTime::createFromFormat('Y-m-d', $date);
    if (!$d || $d->format('Y-m-d') !== $date) error_response('Date must be YYYY-MM-DD', 422);
    json_response(['success' => true, 'data' => attendance_explain($pdo, $eid, $date)]);
}
