<?php
/**
 * Reports, audit log and organisation chart.
 *
 *   GET /reports/attendance?month=YYYY-MM[&format=csv]     per-employee monthly summary     (HR)
 *   GET /reports/attendance-daily?from=&to=[&format=csv]   every attendance record          (HR)
 *   GET /reports/payroll?month=YYYY-MM[&format=csv]                                          (HR)
 *   GET /reports/employees[?format=csv]                                                      (HR)
 *   GET /reports/leaves?year=YYYY[&format=csv]                                               (HR)
 *   GET /reports/points[?format=csv]                                                         (HR)
 *   GET /audit?limit=&entity=                                   who changed what             (admin)
 *   GET /org                                                    departments + reporting lines (everyone)
 */
require_once __DIR__ . '/attendance.php';
require_once __DIR__ . '/payroll.php';
require_once __DIR__ . '/../helpers/points.php';

function handle_reports(string $path, string $method, array $body): void {
    if ($method !== 'GET') error_response('Method not allowed', 405);
    require_hr();
    $pdo  = getDB();
    $name = explode('/', $path)[1] ?? '';
    switch ($name) {
        case 'attendance':       $r = reports_attendance($pdo);       break;
        case 'attendance-daily': $r = reports_attendance_daily($pdo); break;
        case 'payroll':          $r = reports_payroll($pdo);          break;
        case 'employees':        $r = reports_employees($pdo);        break;
        case 'leaves':           $r = reports_leaves($pdo);           break;
        case 'points':           $r = reports_points($pdo);           break;
        default: error_response('Unknown report', 404);
    }
    [$title, $columns, $rows] = $r;
    if (($_GET['format'] ?? '') === 'csv') reports_csv($title, $columns, $rows);
    json_response(['success' => true, 'data' => ['title' => $title, 'columns' => $columns, 'rows' => $rows]]);
}

function reports_csv(string $title, array $columns, array $rows): void {
    header_remove('Content-Type');
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename="' . preg_replace('/[^a-z0-9_-]+/i', '-', $title) . '.csv"');
    $out = fopen('php://output', 'w');
    fwrite($out, "\xEF\xBB\xBF");                                   // UTF-8 BOM so Excel reads Arabic names correctly
    fputcsv($out, array_values($columns));
    foreach ($rows as $r) {
        $line = [];
        foreach (array_keys($columns) as $k) {
            $v = $r[$k] ?? '';
            // neutralise spreadsheet formulas in user-entered text
            if (is_string($v) && $v !== '' && in_array($v[0], ['=', '+', '-', '@'], true) && !is_numeric($v)) $v = "'" . $v;
            $line[] = $v;
        }
        fputcsv($out, $line);
    }
    fclose($out);
    exit;
}

function reports_month(): array {
    [$m, $y] = payroll_split_month($_GET['month'] ?? date('Y-m'));
    return [$m, $y ?? (int)date('Y')];
}

/** Attendance numbers for one employee and month. */
function att_month_stats(PDO $pdo, array $emp, int $month, int $year): array {
    $now   = att_now($pdo);
    $today = $now->format('Y-m-d');
    $first = new DateTime(sprintf('%04d-%02d-01', $year, $month));
    $last  = (clone $first)->modify('last day of this month');
    $from  = $first->format('Y-m-d'); $to = $last->format('Y-m-d');
    $shift = att_shift($pdo, $emp);
    $eid   = (int)$emp['id'];

    $att = [];
    $q = $pdo->prepare("SELECT * FROM attendance WHERE company_id = ? AND employee_id = ? AND date BETWEEN ? AND ?");
    $q->execute([cid(), $eid, $from, $to]);
    foreach ($q->fetchAll() as $r) $att[$r['date']] = $r;
    $hol = [];
    $q = $pdo->prepare("SELECT date FROM holidays WHERE company_id = ? AND date BETWEEN ? AND ?");
    $q->execute([cid(), $from, $to]);
    foreach ($q->fetchAll(PDO::FETCH_COLUMN) as $d) $hol[$d] = true;
    $lv = [];
    $q = $pdo->prepare("SELECT start_date, end_date FROM leaves WHERE company_id = ? AND employee_id = ? AND status = 'approved' AND start_date <= ? AND end_date >= ?");
    $q->execute([cid(), $eid, $to, $from]);
    foreach ($q->fetchAll() as $l) {
        for ($d = new DateTime(max($l['start_date'], $from)); $d->format('Y-m-d') <= min($l['end_date'], $to); $d->modify('+1 day')) $lv[$d->format('Y-m-d')] = true;
    }

    $st = ['workdays' => 0, 'present' => 0, 'late' => 0, 'half_day' => 0, 'absent' => 0, 'leave' => 0, 'hours' => 0.0, 'overtime_hours' => 0.0, 'late_minutes' => 0, 'out_zone_minutes' => 0];
    foreach ($att as $ds => $r) {
        $st['hours'] += (float)$r['hours_worked'];
        $st['overtime_hours'] += (int)$r['overtime_minutes'] / 60;
        $st['out_zone_minutes'] += (int)$r['out_zone_minutes'];
    }
    for ($d = clone $first; $d <= $last; $d->modify('+1 day')) {
        $ds = $d->format('Y-m-d');
        if (!att_is_workday($pdo, $shift, $ds) || isset($hol[$ds])) continue;
        $st['workdays']++;
        if ($ds > $today) continue;
        if (isset($att[ds_key($ds)])) {
            $r = $att[$ds];
            if ($r['status'] === 'late') { $st['late']++; $st['late_minutes'] += (int)$r['late_minutes']; }
            elseif (isset($st[$r['status']])) $st[$r['status']]++;
            continue;
        }
        if (isset($lv[$ds])) { $st['leave']++; continue; }
        if ($ds < $today) $st['absent']++;
    }
    $st['hours'] = round($st['hours'], 2);
    $st['overtime_hours'] = round($st['overtime_hours'], 2);
    return $st;
}
function ds_key(string $d): string { return $d; }

function reports_active_employees(PDO $pdo): array {
    $s = $pdo->prepare(
        "SELECT e.*, d.name AS department_name, s.name AS shift_name, s.start_time AS shift_start, s.end_time AS shift_end, s.days AS shift_days
         FROM employees e LEFT JOIN departments d ON d.id = e.department_id LEFT JOIN shifts s ON s.id = e.shift_id
         WHERE e.company_id = ? AND e.status != 'inactive' ORDER BY e.first_name, e.last_name"
    );
    $s->execute([cid()]);
    return $s->fetchAll();
}

function reports_attendance(PDO $pdo): array {
    att_close_stale($pdo);
    [$m, $y] = reports_month();
    $rows = [];
    foreach (reports_active_employees($pdo) as $e) {
        $st = att_month_stats($pdo, $e, $m, $y);
        $rows[] = array_merge(['employee' => $e['first_name'] . ' ' . $e['last_name'], 'department' => $e['department_name'], 'position' => $e['position']], $st);
    }
    return [sprintf('attendance-%04d-%02d', $y, $m), [
        'employee' => 'Employee', 'department' => 'Department', 'position' => 'Position', 'workdays' => 'Working days', 'present' => 'Present',
        'late' => 'Late', 'half_day' => 'Half days', 'absent' => 'Absent', 'leave' => 'On leave', 'hours' => 'Hours worked',
        'overtime_hours' => 'Overtime hours', 'late_minutes' => 'Late minutes', 'out_zone_minutes' => 'Minutes outside workplace',
    ], $rows];
}

function reports_attendance_daily(PDO $pdo): array {
    att_close_stale($pdo);
    $from = $_GET['from'] ?? date('Y-m-01');
    $to   = $_GET['to'] ?? date('Y-m-d');
    $s = $pdo->prepare(
        "SELECT a.*, CONCAT(e.first_name, ' ', e.last_name) AS employee, d.name AS department
         FROM attendance a JOIN employees e ON e.id = a.employee_id LEFT JOIN departments d ON d.id = e.department_id
         WHERE a.company_id = ? AND a.date BETWEEN ? AND ? ORDER BY a.date, e.first_name LIMIT 5000"
    );
    $s->execute([cid(), $from, $to]);
    return ["attendance-daily-$from-$to", [
        'date' => 'Date', 'employee' => 'Employee', 'department' => 'Department', 'check_in' => 'Check in', 'check_out' => 'Check out', 'status' => 'Status',
        'late_minutes' => 'Late minutes', 'early_leave_minutes' => 'Early leave minutes', 'hours_worked' => 'Hours', 'overtime_minutes' => 'Overtime minutes',
        'out_zone_minutes' => 'Minutes outside', 'flags' => 'Flags', 'source' => 'Source',
    ], $s->fetchAll()];
}

function reports_payroll(PDO $pdo): array {
    [$m, $y] = reports_month();
    $s = $pdo->prepare(
        "SELECT CONCAT(e.first_name, ' ', e.last_name) AS employee, d.name AS department, p.base_salary, p.bonus, p.deductions, p.net_pay, p.status, p.paid_at
         FROM payroll p JOIN employees e ON e.id = p.employee_id LEFT JOIN departments d ON d.id = e.department_id
         WHERE p.company_id = ? AND p.month = ? AND p.year = ? ORDER BY e.first_name"
    );
    $s->execute([cid(), $m, $y]);
    return [sprintf('payroll-%04d-%02d', $y, $m), [
        'employee' => 'Employee', 'department' => 'Department', 'base_salary' => 'Base salary', 'bonus' => 'Bonus / overtime',
        'deductions' => 'Deductions', 'net_pay' => 'Net pay', 'status' => 'Status', 'paid_at' => 'Paid at',
    ], $s->fetchAll()];
}

function reports_employees(PDO $pdo): array {
    $s = $pdo->prepare(
        "SELECT e.*, d.name AS department, CONCAT(m.first_name, ' ', m.last_name) AS manager, sh.name AS shift
         FROM employees e LEFT JOIN departments d ON d.id = e.department_id LEFT JOIN employees m ON m.id = e.manager_id LEFT JOIN shifts sh ON sh.id = e.shift_id
         WHERE e.company_id = ? ORDER BY e.first_name, e.last_name"
    );
    $s->execute([cid()]);
    $rows = array_map(fn($e) => array_merge($e, ['name' => $e['first_name'] . ' ' . $e['last_name']]), $s->fetchAll());
    return ['employees', [
        'name' => 'Name', 'email' => 'Email', 'phone' => 'Phone', 'position' => 'Position', 'department' => 'Department', 'manager' => 'Manager',
        'shift' => 'Shift', 'status' => 'Status', 'start_date' => 'Start date', 'salary' => 'Salary', 'birth_date' => 'Birth date', 'termination_date' => 'End date',
    ], $rows];
}

function reports_leaves(PDO $pdo): array {
    $y = intval($_GET['year'] ?? date('Y'));
    $s = $pdo->prepare(
        "SELECT CONCAT(e.first_name, ' ', e.last_name) AS employee, l.type, l.start_date, l.end_date, l.days, l.status, l.reason
         FROM leaves l JOIN employees e ON e.id = l.employee_id WHERE l.company_id = ? AND YEAR(l.start_date) = ? ORDER BY l.start_date"
    );
    $s->execute([cid(), $y]);
    return ["leaves-$y", [
        'employee' => 'Employee', 'type' => 'Type', 'start_date' => 'From', 'end_date' => 'To', 'days' => 'Days', 'status' => 'Status', 'reason' => 'Reason',
    ], $s->fetchAll()];
}

function reports_points(PDO $pdo): array {
    $rows = points_leaderboard($pdo, 1000);
    return ['points', [
        'rank' => 'Rank', 'name' => 'Employee', 'department_name' => 'Department', 'level_name' => 'Level', 'streak' => 'Green streak',
        'green' => 'Green', 'red' => 'Red', 'black' => 'Black', 'score' => 'Score',
    ], $rows];
}

// ------------------------------------------------------------------ audit log

function handle_audit(string $path, string $method, array $body): void {
    if ($method !== 'GET') error_response('Method not allowed', 405);
    require_admin();
    $pdo = getDB();
    $where = ['company_id = ?']; $args = [cid()];
    if (!empty($_GET['entity'])) { $where[] = 'entity = ?'; $args[] = $_GET['entity']; }
    if (!empty($_GET['q']))      { $where[] = '(action LIKE ? OR details LIKE ? OR user_name LIKE ?)'; $like = '%' . $_GET['q'] . '%'; array_push($args, $like, $like, $like); }
    $limit = isset($_GET['limit']) ? max(1, min(500, intval($_GET['limit']))) : 100;
    $s = $pdo->prepare("SELECT * FROM audit_log WHERE " . implode(' AND ', $where) . " ORDER BY id DESC LIMIT $limit");
    $s->execute($args);
    $rows = $s->fetchAll();
    foreach ($rows as &$r) { $d = $r['details'] ? json_decode($r['details'], true) : null; $r['details'] = $d ?? $r['details']; }
    unset($r);
    json_response(['success' => true, 'data' => $rows]);
}

// ------------------------------------------------------------------ organisation

function handle_org(string $path, string $method, array $body): void {
    if ($method !== 'GET') error_response('Method not allowed', 405);
    $pdo = getDB();
    $emps = $pdo->prepare(
        "SELECT e.id, e.first_name, e.last_name, e.position, e.avatar, e.department_id, e.manager_id
         FROM employees e WHERE e.company_id = ? AND e.status != 'inactive' ORDER BY e.first_name, e.last_name"
    );
    $emps->execute([cid()]);
    $emps = $emps->fetchAll();
    $byDept = [];
    foreach ($emps as $e) $byDept[(int)$e['department_id']][] = $e;

    $ds = $pdo->prepare("SELECT d.id, d.name, d.head_employee_id FROM departments d WHERE d.company_id = ? ORDER BY d.name");
    $ds->execute([cid()]);
    $departments = [];
    foreach ($ds->fetchAll() as $d) {
        $members = $byDept[(int)$d['id']] ?? [];
        $head = null;
        foreach ($members as $m) { if ((int)$m['id'] === (int)$d['head_employee_id']) $head = $m; }
        $departments[] = ['id' => (int)$d['id'], 'name' => $d['name'], 'head' => $head, 'members' => $members];
    }

    // reporting tree
    $nodes = [];
    foreach ($emps as $e) $nodes[(int)$e['id']] = $e + ['reports' => []];
    $roots = [];
    foreach ($nodes as $id => &$n) {
        $mid = (int)($n['manager_id'] ?? 0);
        if ($mid && isset($nodes[$mid])) $nodes[$mid]['reports'][] = &$n; else $roots[] = &$n;
    }
    unset($n);
    json_response(['success' => true, 'data' => ['departments' => $departments, 'unassigned' => $byDept[0] ?? [], 'tree' => array_values($roots)]]);
}
