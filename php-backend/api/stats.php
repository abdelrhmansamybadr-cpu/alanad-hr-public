<?php
/**
 * Stats / Dashboard API handler (company-scoped)
 *
 *   GET /stats            HR dashboard numbers
 *   GET /stats/activity   recent activity feed (array)
 *   GET /stats/me         the employee home dashboard (any signed-in user with an employee record)
 */
require_once __DIR__ . '/attendance.php';
require_once __DIR__ . '/../helpers/points.php';

function handle_stats(string $path, string $method, array $body): void {
    if ($method !== 'GET') {
        error_response('Method not allowed', 405);
    }
    $pdo  = getDB();
    $sub  = explode('/', $path)[1] ?? '';

    if ($sub === 'me') {
        stats_me($pdo);
    }
    require_hr();
    if ($sub === 'activity') {
        stats_activity($pdo);
    }
    if ($sub === 'wellbeing') {
        stats_wellbeing($pdo);
    }
    stats_dashboard($pdo);
}

function stats_count(PDO $pdo, string $sql, array $params = []): int {
    $s = $pdo->prepare($sql);
    $s->execute($params);
    return (int)$s->fetchColumn();
}

function stats_dashboard(PDO $pdo): void {
    $c     = cid();
    $now   = attendance_now($pdo);
    $today = $now->format('Y-m-d');

    $total    = stats_count($pdo, "SELECT COUNT(*) FROM employees WHERE company_id = ? AND status != 'inactive'", [$c]);
    $active   = stats_count($pdo, "SELECT COUNT(*) FROM employees WHERE company_id = ? AND status = 'active'", [$c]);
    $onLeave  = stats_count($pdo, "SELECT COUNT(DISTINCT employee_id) FROM leaves WHERE company_id = ? AND status = 'approved' AND start_date <= ? AND end_date >= ?", [$c, $today, $today]);
    $present  = stats_count($pdo, "SELECT COUNT(*) FROM attendance WHERE company_id = ? AND date = ? AND status IN ('present','late','half_day')", [$c, $today]);
    $late     = stats_count($pdo, "SELECT COUNT(*) FROM attendance WHERE company_id = ? AND date = ? AND status = 'late'", [$c, $today]);
    $checked  = stats_count($pdo, "SELECT COUNT(*) FROM attendance WHERE company_id = ? AND date = ?", [$c, $today]);
    $half     = stats_count($pdo, "SELECT COUNT(*) FROM attendance WHERE company_id = ? AND date = ? AND status = 'half_day'", [$c, $today]);
    $outside  = stats_count($pdo, "SELECT COUNT(*) FROM attendance WHERE company_id = ? AND date = ? AND check_out IS NULL AND last_ping_inside = 0", [$c, $today]);

    // Absent = working people whose shift is over with no check-in; "not in yet" = shift still running
    att_close_stale($pdo);
    $absent = 0; $notIn = 0;
    $holiday = attendance_holiday($pdo, $today);
    $es = $pdo->prepare(
        "SELECT e.*, s.name AS shift_name, s.start_time AS shift_start, s.end_time AS shift_end, s.days AS shift_days,
                (SELECT 1 FROM attendance a WHERE a.employee_id = e.id AND a.date = ? AND a.company_id = e.company_id LIMIT 1) AS has_rec
         FROM employees e LEFT JOIN shifts s ON s.id = e.shift_id WHERE e.company_id = ? AND e.status != 'inactive'"
    );
    $es->execute([$today, $c]);
    foreach ($es->fetchAll() as $e) {
        if ($e['has_rec']) continue;
        $st = attendance_day_status($pdo, $e, $today, $now, null, attendance_on_leave($pdo, (int)$e['id'], $today), $holiday);
        if ($st === 'absent') $absent++; elseif ($st === 'not_in') $notIn++;
    }

    $pendingLeaves   = stats_count($pdo, "SELECT COUNT(*) FROM leaves WHERE company_id = ? AND status = 'pending'", [$c]);
    $pendingRequests = stats_count($pdo, "SELECT COUNT(*) FROM requests WHERE company_id = ? AND status = 'pending'", [$c]);

    $payroll = $pdo->prepare("SELECT COALESCE(SUM(net_pay), 0) FROM payroll WHERE company_id = ? AND month = ? AND year = ? AND status != 'cancelled'");
    $payroll->execute([$c, (int)$now->format('n'), (int)$now->format('Y')]);

    $dept = $pdo->prepare(
        "SELECT d.name, COUNT(e.id) AS count FROM departments d
         LEFT JOIN employees e ON e.department_id = d.id AND e.status != 'inactive'
         WHERE d.company_id = ? GROUP BY d.id ORDER BY count DESC"
    );
    $dept->execute([$c]);

    // Attendance for the last 7 days (for the trend chart)
    $trend = $pdo->prepare(
        "SELECT date, SUM(status IN ('present','late','half_day')) AS present, SUM(status = 'late') AS late
         FROM attendance WHERE company_id = ? AND date >= ? GROUP BY date ORDER BY date"
    );
    $trend->execute([$c, (clone $now)->modify('-6 days')->format('Y-m-d')]);

    // Birthdays and work anniversaries in the next 30 days
    $events = [];
    $emps = $pdo->prepare("SELECT id, first_name, last_name, avatar, birth_date, start_date FROM employees WHERE company_id = ? AND status != 'inactive'");
    $emps->execute([$c]);
    foreach ($emps->fetchAll() as $e) {
        foreach (['birth_date' => 'birthday', 'start_date' => 'anniversary'] as $col => $type) {
            if (empty($e[$col])) continue;
            $d = DateTime::createFromFormat('Y-m-d', $e[$col]);
            if (!$d) continue;
            $next = DateTime::createFromFormat('Y-m-d', $now->format('Y') . '-' . $d->format('m-d'));
            if (!$next) continue;                                  // 29 Feb
            if ($next->format('Y-m-d') < $today) $next->modify('+1 year');
            $in = (int)$now->setTime(0, 0)->diff($next->setTime(0, 0))->format('%a');
            if ($in <= 30 && !($type === 'anniversary' && (int)$next->format('Y') - (int)$d->format('Y') < 1)) {
                $events[] = ['type' => $type, 'employee_id' => (int)$e['id'], 'name' => $e['first_name'] . ' ' . $e['last_name'],
                             'avatar' => $e['avatar'], 'date' => $next->format('Y-m-d'), 'in_days' => $in,
                             'years' => $type === 'anniversary' ? (int)$next->format('Y') - (int)$d->format('Y') : null];
            }
        }
    }
    usort($events, fn($a, $b) => $a['in_days'] <=> $b['in_days']);

    $recent = $pdo->prepare(
        "SELECT l.*, CONCAT(e.first_name, ' ', e.last_name) AS employee_name
         FROM leaves l JOIN employees e ON e.id = l.employee_id
         WHERE l.company_id = ? ORDER BY l.created_at DESC LIMIT 5"
    );
    $recent->execute([$c]);

    $newHires = stats_count($pdo, "SELECT COUNT(*) FROM employees WHERE company_id = ? AND status != 'inactive' AND start_date >= ?", [$c, (clone $now)->modify('-30 days')->format('Y-m-d')]);

    json_response(['success' => true, 'data' => [
        'totalEmployees'   => $total,
        'activeEmployees'  => $active,
        'onLeave'          => $onLeave,
        'openPositions'    => stats_count($pdo, "SELECT COUNT(*) FROM jobs WHERE company_id = ? AND status = 'open'", [$c]),
        'pendingLeaves'    => $pendingLeaves,
        'pendingRequests'  => $pendingRequests,
        'newApplications'  => stats_count($pdo, "SELECT COUNT(*) FROM applications WHERE company_id = ? AND status = 'new'", [$c]),
        'upcomingReviews'  => stats_count($pdo, "SELECT COUNT(*) FROM reviews WHERE company_id = ? AND status = 'draft'", [$c]),
        'totalPayroll'     => (float)$payroll->fetchColumn(),
        'todayAttendance'  => $checked,
        'presentToday'     => $present,
        'lateToday'        => $late,
        'absentToday'      => $absent,
        'notInYet'         => $notIn,
        'halfDayToday'     => $half,
        'outsideNow'       => $outside,
        'pendingCorrections' => stats_count($pdo, "SELECT COUNT(*) FROM requests WHERE company_id = ? AND status = 'pending' AND type IN ('attendance_correction','profile_change')", [$c]),
        'topPerformers'    => array_slice(points_leaderboard($pdo, 3), 0, 3),
        'attendanceRate'   => $total > 0 ? round(($present / $total) * 100, 1) : 0,
        'newHires'         => $newHires,
        'deptBreakdown'    => $dept->fetchAll(),
        'attendanceTrend'  => $trend->fetchAll(),
        'upcomingEvents'   => array_slice($events, 0, 10),
        'recentLeaves'     => $recent->fetchAll(),
    ]]);
}

function stats_activity(PDO $pdo): void {
    $c = cid();
    $items = [];

    $q = $pdo->prepare(
        "SELECT l.type, l.status, l.created_at, CONCAT(e.first_name, ' ', e.last_name) AS emp
         FROM leaves l LEFT JOIN employees e ON e.id = l.employee_id
         WHERE l.company_id = ? ORDER BY l.created_at DESC LIMIT 5"
    );
    $q->execute([$c]);
    foreach ($q->fetchAll() as $r) {
        $items[] = ['type' => 'leave', 'title' => 'Leave Request', 'desc' => trim(($r['emp'] ?? 'Employee') . ' - ' . $r['type']),
                    'status' => $r['status'], 'date' => $r['created_at']];
    }

    $q = $pdo->prepare(
        "SELECT a.applicant_name, a.status, a.applied_at, j.title
         FROM applications a LEFT JOIN jobs j ON j.id = a.job_id
         WHERE a.company_id = ? ORDER BY a.applied_at DESC LIMIT 5"
    );
    $q->execute([$c]);
    foreach ($q->fetchAll() as $r) {
        $items[] = ['type' => 'application', 'title' => 'New Application',
                    'desc' => $r['applicant_name'] . ' - ' . ($r['title'] ?? 'Unknown Job'), 'status' => $r['status'], 'date' => $r['applied_at']];
    }

    $q = $pdo->prepare("SELECT title, priority, created_at FROM announcements WHERE company_id = ? ORDER BY created_at DESC LIMIT 3");
    $q->execute([$c]);
    foreach ($q->fetchAll() as $r) {
        $items[] = ['type' => 'announcement', 'title' => 'Announcement', 'desc' => $r['title'], 'status' => $r['priority'], 'date' => $r['created_at']];
    }

    $q = $pdo->prepare("SELECT month, year, status, created_at FROM payroll WHERE company_id = ? ORDER BY created_at DESC LIMIT 3");
    $q->execute([$c]);
    foreach ($q->fetchAll() as $r) {
        $items[] = ['type' => 'payroll', 'title' => 'Payroll', 'desc' => $r['month'] . '/' . $r['year'], 'status' => $r['status'], 'date' => $r['created_at']];
    }

    usort($items, fn($a, $b) => strcmp((string)$b['date'], (string)$a['date']));
    json_response(['success' => true, 'data' => array_slice($items, 0, 10)]);
}

/** Employee home: everything the mobile "Home" tab needs in one request. */
function stats_me(PDO $pdo): void {
    $c    = cid();
    $emp  = own_employee_id();
    $now  = attendance_now($pdo);
    $today = $now->format('Y-m-d');

    $unread = stats_count($pdo, "SELECT COUNT(*) FROM notifications WHERE company_id = ? AND user_id = ? AND read_at IS NULL", [$c, (int)me()['id']]);

    $nextHoliday = $pdo->prepare("SELECT name, date FROM holidays WHERE company_id = ? AND date >= ? ORDER BY date LIMIT 1");
    $nextHoliday->execute([$c, $today]);

    // Colleagues on approved leave today
    $out = $pdo->prepare(
        "SELECT e.id, CONCAT(e.first_name, ' ', e.last_name) AS name, e.avatar, l.end_date
         FROM leaves l JOIN employees e ON e.id = l.employee_id
         WHERE l.company_id = ? AND l.status = 'approved' AND l.start_date <= ? AND l.end_date >= ? AND e.id != ?
         ORDER BY e.first_name LIMIT 12"
    );
    $out->execute([$c, $today, $today, $emp]);

    $ann = $pdo->prepare("SELECT id, title, priority, created_at FROM announcements WHERE company_id = ? ORDER BY created_at DESC LIMIT 3");
    $ann->execute([$c]);

    $month = $emp > 0 ? (function () use ($pdo, $c, $emp, $now) {
        $s = $pdo->prepare(
            "SELECT SUM(status IN ('present','late','half_day')) AS present, SUM(status = 'late') AS late, COALESCE(SUM(hours_worked), 0) AS hours
             FROM attendance WHERE company_id = ? AND employee_id = ? AND MONTH(date) = ? AND YEAR(date) = ?"
        );
        $s->execute([$c, $emp, (int)$now->format('n'), (int)$now->format('Y')]);
        return $s->fetch();
    })() : null;

    $balances = $emp > 0 ? leaves_balance_for_stats($pdo, $emp, (int)$now->format('Y')) : [];

    $pendingApprovals = 0;
    if (is_hr()) {
        $pendingApprovals = stats_count($pdo, "SELECT COUNT(*) FROM leaves WHERE company_id = ? AND status = 'pending'", [$c])
                          + stats_count($pdo, "SELECT COUNT(*) FROM requests WHERE company_id = ? AND status = 'pending'", [$c]);
    } elseif ($emp > 0) {
        $pendingApprovals = stats_count($pdo, "SELECT COUNT(*) FROM leaves l JOIN employees e ON e.id = l.employee_id WHERE l.company_id = ? AND l.status = 'pending' AND e.manager_id = ?", [$c, $emp])
                          + stats_count($pdo, "SELECT COUNT(*) FROM requests r JOIN employees e ON e.id = r.employee_id WHERE r.company_id = ? AND r.status = 'pending' AND e.manager_id = ?", [$c, $emp]);
    }

    json_response(['success' => true, 'data' => [
        'unread_notifications' => $unread,
        'next_holiday'         => $nextHoliday->fetch() ?: null,
        'on_leave_today'       => $out->fetchAll(),
        'announcements'        => $ann->fetchAll(),
        'month'                => $month,
        'leave_balances'       => $balances,
        'pending_approvals'    => $pendingApprovals,
        'is_team_lead'         => has_direct_reports($pdo),
        'points'               => $emp > 0 ? stats_points_brief($pdo, $emp) : null,
    ]]);
}

function leaves_balance_for_stats(PDO $pdo, int $employeeId, int $year): array {
    require_once __DIR__ . '/leaves.php';
    return leaves_balance($pdo, $employeeId, $year);
}


function stats_points_brief(PDO $pdo, int $employeeId): ?array {
    $cfg = points_config($pdo);
    if (!$cfg['enabled']) return null;
    $sum = points_summary($pdo, $employeeId);
    return [
        'green' => $sum['net']['green'], 'red' => $sum['net']['red'], 'black' => $sum['net']['black'],
        'level' => $sum['level'], 'level_name' => $sum['level_name'], 'streak' => $sum['streak'], 'streak_target' => $sum['streak_target'],
    ];
}


/**
 * GET /stats/wellbeing  quiet signals that someone may need attention (HR only). These are prompts for a
 * friendly conversation, never a score or a punishment.
 */
function stats_wellbeing(PDO $pdo): void {
    $c = cid();
    $today = attendance_now($pdo)->format('Y-m-d');
    $from30 = (new DateTime($today))->modify('-30 days')->format('Y-m-d');
    $yearAgo = (new DateTime($today))->modify('-1 year')->format('Y-m-d');
    $person = fn(array $r, string $detail) => ['employee_id' => (int)$r['id'], 'name' => $r['name'], 'avatar' => $r['avatar'] ?? null, 'position' => $r['position'] ?? null, 'detail' => $detail];

    // 1. a year or more without taking any approved leave
    $s = $pdo->prepare(
        "SELECT e.id, CONCAT(e.first_name, ' ', e.last_name) AS name, e.avatar, e.position, e.start_date FROM employees e
         WHERE e.company_id = ? AND e.status != 'inactive' AND e.start_date IS NOT NULL AND e.start_date <= ?
           AND NOT EXISTS (SELECT 1 FROM leaves l WHERE l.employee_id = e.id AND l.status = 'approved' AND l.end_date >= ?)
         ORDER BY e.start_date LIMIT 20"
    );
    $s->execute([$c, $yearAgo, $yearAgo]);
    $noLeave = array_map(fn($r) => $person($r, (string)$r['start_date']), $s->fetchAll());

    // 2. working a lot beyond the shift (average of 45+ minutes a day over at least 8 days)
    $s = $pdo->prepare(
        "SELECT e.id, CONCAT(e.first_name, ' ', e.last_name) AS name, e.avatar, e.position, COUNT(*) AS days, COALESCE(SUM(a.overtime_minutes), 0) AS ot
         FROM attendance a JOIN employees e ON e.id = a.employee_id
         WHERE a.company_id = ? AND a.date >= ? AND a.check_in IS NOT NULL AND e.status != 'inactive'
         GROUP BY e.id HAVING days >= 8 AND ot / days >= 45 ORDER BY ot DESC LIMIT 20"
    );
    $s->execute([$c, $from30]);
    $overtime = array_map(fn($r) => $person($r, round($r['ot'] / 60, 1) . ' h / ' . $r['days'] . ' d'), $s->fetchAll());

    // 3. often late lately (6 or more late, half-day or absent days in 30 days)
    $s = $pdo->prepare(
        "SELECT e.id, CONCAT(e.first_name, ' ', e.last_name) AS name, e.avatar, e.position, COUNT(*) AS n
         FROM attendance a JOIN employees e ON e.id = a.employee_id
         WHERE a.company_id = ? AND a.date >= ? AND a.status IN ('late','half_day','absent') AND e.status != 'inactive'
         GROUP BY e.id HAVING n >= 6 ORDER BY n DESC LIMIT 20"
    );
    $s->execute([$c, $from30]);
    $rough = array_map(fn($r) => $person($r, (string)$r['n']), $s->fetchAll());

    json_response(['success' => true, 'data' => [
        'total' => count($noLeave) + count($overtime) + count($rough),
        'signals' => [
            ['key' => 'no_leave', 'title' => 'No leave taken in over a year', 'employees' => $noLeave],
            ['key' => 'overtime', 'title' => 'Regularly working beyond the shift', 'employees' => $overtime],
            ['key' => 'rough_patch', 'title' => 'Many late or missed days this month', 'employees' => $rough],
        ],
    ]]);
}
