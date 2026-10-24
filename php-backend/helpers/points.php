<?php
/**
 * Reward points.
 *
 *   green  = on time in and on time out        (a good day)
 *   red    = half day (and optionally late)
 *   black  = absent
 *
 * Greens cancel penalties (defaults: 2 green remove 1 red, 5 green remove 1 black) and
 * every `streak_days` consecutive green days raise the employee one level.
 * Points are derived from attendance and stored once per day in points_ledger.
 */
require_once __DIR__ . '/policy.php';
require_once __DIR__ . '/../api/attendance.php';

function points_today(PDO $pdo): string { return att_now($pdo)->format('Y-m-d'); }

/** The colour an employee earns for a past (or finished) day, or null when the day does not count. */
function points_day_color(PDO $pdo, array $emp, string $date, array $cfg, string $today): ?array {
    $shift = att_shift($pdo, $emp);
    if (!att_is_workday($pdo, $shift, $date)) return null;
    if (attendance_holiday($pdo, $date)) return null;
    if (attendance_on_leave($pdo, (int)$emp['id'], $date)) return null;

    $s = $pdo->prepare("SELECT * FROM attendance WHERE company_id = ? AND employee_id = ? AND date = ? LIMIT 1");
    $s->execute([cid(), $emp['id'], $date]);
    $rec = $s->fetch();
    $map = function (string $colour, string $reason): array { return [$colour, $reason]; };

    if (!$rec) {
        if ($date >= $today) return null;
        return $map($cfg['absent_color'], 'absent');
    }
    $flags = array_filter(explode(',', (string)$rec['flags']));
    switch ($rec['status']) {
        case 'absent':   return $map($cfg['absent_color'], 'absent');
        case 'half_day': return $map($cfg['half_day_color'], 'half_day');
        case 'late':     return $map($cfg['late_color'], 'late');
    }
    if (empty($rec['check_out'])) {
        if ($date >= $today && empty($rec['closed'])) return null;             // still at work
        return $map($cfg['missed_checkout_color'], 'missed_checkout');
    }
    $p = att_policy($pdo);
    if ((int)$rec['early_leave_minutes'] > (int)$p['early_leave_grace_minutes']) return $map('none', 'early_leave');
    return $map('green', 'on_time');
}

function points_upsert_auto(PDO $pdo, int $employeeId, string $date, string $colour, string $reason): void {
    $pdo->prepare(
        "INSERT INTO points_ledger (company_id, employee_id, date, color, reason, source, auto_key)
         VALUES (?, ?, ?, ?, ?, 'auto', ?)
         ON DUPLICATE KEY UPDATE color = VALUES(color), reason = VALUES(reason), date = VALUES(date)"
    )->execute([cid(), $employeeId, $date, $colour, $reason, $date]);
}

function points_has_account(PDO $pdo, int $employeeId): bool {
    $s = $pdo->prepare("SELECT 1 FROM users WHERE company_id = ? AND employee_id = ? AND role = 'employee' AND status = 'active' LIMIT 1");
    $s->execute([cid(), $employeeId]);
    return (bool)$s->fetchColumn();
}

/** Re-evaluate one day after attendance for it changed (correction, HR edit, auto-close). */
function points_reeval(PDO $pdo, int $employeeId, string $date): void {
    $cfg = points_config($pdo);
    if (!$cfg['enabled']) return;
    $lv = $pdo->prepare("SELECT processed_until FROM employee_levels WHERE employee_id = ? AND company_id = ?");
    $lv->execute([$employeeId, cid()]);
    $row = $lv->fetch();
    if (!$row) return;                                    // never synced yet: it will be picked up by the next sync
    $emp = att_employee_row($pdo, $employeeId);
    if (!$emp) return;
    $today = points_today($pdo);
    $r = points_day_color($pdo, $emp, $date, $cfg, $today);
    if ($r === null) {
        $pdo->prepare("DELETE FROM points_ledger WHERE employee_id = ? AND auto_key = ? AND source = 'auto' AND voided = 0")->execute([$employeeId, $date]);
    } else {
        points_upsert_auto($pdo, $employeeId, $date, $r[0], $r[1]);
    }
}

/** Catch an employee's points up to today. Safe to call often. */
function points_sync_employee(PDO $pdo, int $employeeId): void {
    $cfg = points_config($pdo);
    if (!$cfg['enabled']) return;
    $emp = att_employee_row($pdo, $employeeId);
    if (!$emp || $emp['status'] === 'inactive' || !points_has_account($pdo, $employeeId)) return;

    att_close_stale($pdo, $employeeId);
    $today = points_today($pdo);
    $yesterday = (new DateTime($today))->modify('-1 day')->format('Y-m-d');

    $lv = $pdo->prepare("SELECT * FROM employee_levels WHERE employee_id = ? AND company_id = ?");
    $lv->execute([$employeeId, cid()]);
    $row = $lv->fetch();
    if (!$row) {
        // Points start the day AFTER the account first shows up here (the first, partial day never counts against anyone)
        $pdo->prepare("INSERT INTO employee_levels (employee_id, company_id, level, processed_until) VALUES (?, ?, 0, ?)")->execute([$employeeId, cid(), $today]);
        $row = ['level' => 0, 'processed_until' => $today];
    }
    $from = (new DateTime($row['processed_until'] ?: $yesterday))->modify('+1 day');
    $to   = new DateTime($yesterday);
    $n = 0;
    for ($d = clone $from; $d <= $to && $n < 400; $d->modify('+1 day'), $n++) {
        $r = points_day_color($pdo, $emp, $d->format('Y-m-d'), $cfg, $today);
        if ($r !== null) points_upsert_auto($pdo, $employeeId, $d->format('Y-m-d'), $r[0], $r[1]);
    }
    // today counts once the day's attendance is complete
    $t = points_day_color($pdo, $emp, $today, $cfg, $today);
    if ($t !== null) points_upsert_auto($pdo, $employeeId, $today, $t[0], $t[1]);
    if ($to >= $from) {
        $pdo->prepare("UPDATE employee_levels SET processed_until = ? WHERE employee_id = ? AND company_id = ?")->execute([$yesterday, $employeeId, cid()]);
    }
    // (a row created today keeps processed_until = today until tomorrow's first sync)

    // Level-up notification
    $sum = points_summary_from_rows($pdo, $employeeId, $cfg);
    if ($sum['level'] > (int)$row['level']) {
        $pdo->prepare("UPDATE employee_levels SET level = ? WHERE employee_id = ? AND company_id = ?")->execute([$sum['level'], $employeeId, cid()]);
        notify_employee($pdo, $employeeId, 'level_up', 'Level up!',
            'You reached ' . $sum['level_name'] . ' after ' . $cfg['streak_days'] . ' green days in a row. Keep it up!', ['level' => $sum['level']]);
    }
}

function points_sync_company(PDO $pdo): void {
    $s = $pdo->prepare("SELECT e.id FROM employees e JOIN users u ON u.employee_id = e.id AND u.role = 'employee' AND u.status = 'active'
                        WHERE e.company_id = ? AND e.status != 'inactive' LIMIT 500");
    $s->execute([cid()]);
    foreach ($s->fetchAll(PDO::FETCH_COLUMN) as $id) points_sync_employee($pdo, (int)$id);
}

// ------------------------------------------------------------------ summaries

/** Replay a list of auto rows (ascending) into [level, streak, best_streak]. */
function points_replay(array $autoRows, int $streakDays): array {
    $streak = 0; $level = 0; $best = 0;
    foreach ($autoRows as $r) {
        if ((int)$r['voided'] === 1) continue;              // excused by HR: neither counts nor breaks
        if ($r['color'] === 'green') {
            $streak++;
            $best = max($best, $streak);
            if ($streak >= $streakDays) { $level++; $streak = 0; }
        } else {
            $streak = 0;
        }
    }
    return [$level, $streak, $best];
}

/** Greens cancel penalties. */
function points_net(array $raw, array $cfg): array {
    $g = $raw['green']; $r = $raw['red']; $b = $raw['black'];
    $cancelR = 0; $cancelB = 0; $spent = 0;
    $steps = $cfg['cancel_order'] === 'red_first' ? ['red', 'black'] : ['black', 'red'];
    foreach ($steps as $step) {
        if ($step === 'black') { $n = min($b, intdiv($g, $cfg['black_cost'])); $cancelB = $n; $g -= $n * $cfg['black_cost']; $spent += $n * $cfg['black_cost']; }
        else                   { $n = min($r, intdiv($g, $cfg['red_cost']));   $cancelR = $n; $g -= $n * $cfg['red_cost'];   $spent += $n * $cfg['red_cost']; }
    }
    return [
        'net' => ['green' => $g, 'red' => $r - $cancelR, 'black' => $b - $cancelB],
        'cancelled' => ['red' => $cancelR, 'black' => $cancelB], 'green_spent' => $spent,
    ];
}

function points_level_name(array $cfg, int $level): string {
    $names = $cfg['levels'];
    return $names[min($level, count($names) - 1)] ?? ('Level ' . $level);
}

function points_summary_from_rows(PDO $pdo, int $employeeId, array $cfg): array {
    $s = $pdo->prepare("SELECT id, date, color, reason, source, note, voided FROM points_ledger WHERE company_id = ? AND employee_id = ? ORDER BY date ASC, id ASC");
    $s->execute([cid(), $employeeId]);
    $rows = $s->fetchAll();
    $raw = ['green' => 0, 'red' => 0, 'black' => 0];
    $auto = [];
    $month = ['green' => 0, 'red' => 0, 'black' => 0, 'none' => 0];
    $thisMonth = substr(points_today($pdo), 0, 7);
    foreach ($rows as $r) {
        if ((int)$r['voided'] === 1) continue;
        if (isset($raw[$r['color']])) $raw[$r['color']]++;
        if (substr($r['date'], 0, 7) === $thisMonth && isset($month[$r['color']])) $month[$r['color']]++;
        if ($r['source'] === 'auto') $auto[] = $r;
    }
    [$level, $streak, $best] = points_replay(array_filter($rows, fn($r) => $r['source'] === 'auto'), (int)$cfg['streak_days']);
    $net = points_net($raw, $cfg);
    $history = array_slice(array_reverse($rows), 0, 60);

    return array_merge([
        'enabled' => (bool)$cfg['enabled'],
        'raw' => $raw, 'streak' => $streak, 'best_streak' => $best, 'streak_target' => (int)$cfg['streak_days'],
        'level' => $level, 'level_name' => points_level_name($cfg, $level), 'next_level_name' => points_level_name($cfg, $level + 1),
        'this_month' => $month, 'history' => $history,
        'score' => $net['net']['green'] * 10 - $net['net']['red'] * 20 - $net['net']['black'] * 50 + $level * 100 + $streak,
    ], $net);
}

function points_summary(PDO $pdo, int $employeeId): array {
    $cfg = points_config($pdo);
    if ($cfg['enabled']) points_sync_employee($pdo, $employeeId);
    $sum = points_summary_from_rows($pdo, $employeeId, $cfg);
    $sum['rules'] = [
        'red_cost' => (int)$cfg['red_cost'], 'black_cost' => (int)$cfg['black_cost'], 'streak_days' => (int)$cfg['streak_days'],
        'late_color' => $cfg['late_color'], 'half_day_color' => $cfg['half_day_color'], 'absent_color' => $cfg['absent_color'],
        'cancel_order' => $cfg['cancel_order'], 'levels' => $cfg['levels'],
    ];
    return $sum;
}

function points_leaderboard(PDO $pdo, int $limit = 50): array {
    $cfg = points_config($pdo);
    if (!$cfg['enabled']) return [];
    points_sync_company($pdo);
    $emps = $pdo->prepare("SELECT e.id, CONCAT(e.first_name, ' ', e.last_name) AS name, e.avatar, e.position, d.name AS department_name
                           FROM employees e JOIN users u ON u.employee_id = e.id AND u.role = 'employee' AND u.status = 'active'
                           LEFT JOIN departments d ON d.id = e.department_id
                           WHERE e.company_id = ? AND e.status != 'inactive'");
    $emps->execute([cid()]);
    $list = $emps->fetchAll();
    $led = $pdo->prepare("SELECT employee_id, date, color, source, voided FROM points_ledger WHERE company_id = ? ORDER BY date ASC, id ASC");
    $led->execute([cid()]);
    $by = [];
    foreach ($led->fetchAll() as $r) $by[$r['employee_id']][] = $r;

    $out = [];
    foreach ($list as $e) {
        $rows = $by[$e['id']] ?? [];
        $raw = ['green' => 0, 'red' => 0, 'black' => 0];
        foreach ($rows as $r) { if ((int)$r['voided'] === 0 && isset($raw[$r['color']])) $raw[$r['color']]++; }
        [$level, $streak] = points_replay(array_filter($rows, fn($r) => $r['source'] === 'auto'), (int)$cfg['streak_days']);
        $net = points_net($raw, $cfg);
        $out[] = [
            'employee_id' => (int)$e['id'], 'name' => $e['name'], 'avatar' => $e['avatar'], 'position' => $e['position'], 'department_name' => $e['department_name'],
            'level' => $level, 'level_name' => points_level_name($cfg, $level), 'streak' => $streak,
            'green' => $net['net']['green'], 'red' => $net['net']['red'], 'black' => $net['net']['black'],
            'score' => $net['net']['green'] * 10 - $net['net']['red'] * 20 - $net['net']['black'] * 50 + $level * 100 + $streak,
        ];
    }
    usort($out, fn($a, $b) => [$b['level'], $b['streak'], $b['green'], $a['name']] <=> [$a['level'], $a['streak'], $a['green'], $b['name']]);
    foreach ($out as $i => &$o) $o['rank'] = $i + 1;
    unset($o);
    return array_slice($out, 0, $limit);
}
