<?php
/**
 * Attendance trust and transparency:
 *   - fake-location and shared-phone checks      (attendance_prepare / attendance_save_security)
 *   - offline check-in / out synced later         (client_ts in attendance_prepare)
 *   - "why was my day marked like this?"          (attendance_explain)
 */
require_once __DIR__ . '/policy.php';

const ATT_SECURITY_LABELS = [
    'mock_location' => 'Fake location reported by the phone',
    'shared_device' => 'Same phone used by another employee today',
    'offline_sync'  => 'Recorded offline and synced later',
];

/**
 * Runs before a check-in / check-out / ping is processed. May stop the request, may move the clock to the
 * moment an offline action really happened, and returns the security flags to store with the record.
 */
function attendance_prepare(array $body, PDO $pdo, string $action, int $employeeId): array {
    $flags = [];
    $p = att_policy($pdo);
    $name = null;
    $who = function () use ($pdo, $employeeId, &$name): string {
        if ($name === null) { $e = att_employee_row($pdo, $employeeId); $name = $e ? trim($e['first_name'] . ' ' . $e['last_name']) : 'An employee'; }
        return $name;
    };

    // ---- offline action synced later
    if (isset($body['client_ts']) && is_numeric($body['client_ts']) && in_array($action, ['check_in', 'check_out'], true) && (int)$p['offline_max_hours'] > 0) {
        $real = att_now($pdo);
        $at = new DateTime('@' . (int)$body['client_ts']);
        $at->setTimezone($real->getTimezone());
        $age = $real->getTimestamp() - $at->getTimestamp();
        if ($age < -300) error_response('The time on your phone looks wrong. Fix it and try again.', 422);
        if ($age > (int)$p['offline_max_hours'] * 3600) error_response('This offline action is too old to sync. Ask HR to add it.', 422);
        if ($age > 90) {
            $GLOBALS['HR_NOW_OVERRIDE'] = $at;
            $flags[] = 'offline_sync';
        }
    }

    // ---- fake GPS
    if (!empty($body['mock']) && filter_var($body['mock'], FILTER_VALIDATE_BOOLEAN)) {
        if (!empty($p['block_mock_location'])) {
            notify_hr($pdo, 'security_flag', 'Fake location blocked', $who() . ' tried to ' . str_replace('_', ' ', $action) . ' with a fake location.', ['employee_id' => $employeeId]);
            error_response('Your phone reports a fake location. Turn off any mock-location app and try again.', 422);
        }
        $flags[] = 'mock_location';
        notify_hr($pdo, 'security_flag', 'Fake location reported', $who() . ': the phone reported a fake location.', ['employee_id' => $employeeId]);
    }

    // ---- one phone, two people
    $device = isset($body['device_id']) ? substr(preg_replace('/[^a-zA-Z0-9\-]/', '', (string)$body['device_id']), 0, 64) : '';
    if ($device !== '' && $action === 'check_in') {
        $s = $pdo->prepare("SELECT employee_id FROM attendance WHERE company_id = ? AND date = ? AND device_id = ? AND employee_id != ? LIMIT 1");
        $s->execute([cid(), att_now($pdo)->format('Y-m-d'), $device, $employeeId]);
        if ($s->fetchColumn() !== false) {
            if (!empty($p['block_shared_device'])) error_response('A colleague already checked in from this phone today.', 422);
            $flags[] = 'shared_device';
            notify_hr($pdo, 'security_flag', 'Shared phone', $who() . ' checked in from a phone a colleague already used today.', ['employee_id' => $employeeId]);
        }
    }
    return ['flags' => $flags, 'device' => $device !== '' ? $device : null];
}

/** Store the flags (merged with earlier ones) and the phone id on the attendance row. */
function attendance_save_security(PDO $pdo, int $attendanceId, array $trust): void {
    if (!$trust['flags'] && !$trust['device']) return;
    $cur = $pdo->prepare("SELECT security_flags FROM attendance WHERE id = ? AND company_id = ?");
    $cur->execute([$attendanceId, cid()]);
    $have = array_filter(explode(',', (string)$cur->fetchColumn()));
    $merged = array_values(array_unique(array_merge($have, $trust['flags'])));
    $pdo->prepare("UPDATE attendance SET security_flags = ?, device_id = COALESCE(?, device_id) WHERE id = ? AND company_id = ?")
        ->execute([$merged ? implode(',', $merged) : null, $trust['device'], $attendanceId, cid()]);
}

/**
 * Plain-language reasons behind a day's result, built from the same numbers the rules use.
 * Each reason has a stable `code` and `params` (so the apps can translate it) and an English `text`.
 */
function attendance_explain(PDO $pdo, int $employeeId, string $date): array {
    $emp = att_employee_row($pdo, $employeeId);
    if (!$emp) error_response('Employee not found', 404);
    $p = att_policy($pdo);
    $c = company_get($pdo, cid());
    $grace = (int)($c['late_grace_minutes'] ?? 15);
    $shift = att_shift($pdo, $emp);
    $reasons = [];
    $add = function (string $code, string $text, array $params = [], string $tone = 'info') use (&$reasons) {
        $reasons[] = ['code' => $code, 'text' => $text, 'params' => (object)$params, 'tone' => $tone];
    };
    $add('shift', "Your shift is {$shift['start']} to {$shift['end']}; you are on time until $grace min after it starts.", ['start' => $shift['start'], 'end' => $shift['end'], 'grace' => $grace]);

    $s = $pdo->prepare("SELECT * FROM attendance WHERE company_id = ? AND employee_id = ? AND date = ? LIMIT 1");
    $s->execute([cid(), $employeeId, $date]);
    $r = $s->fetch();
    $status = $r['status'] ?? null;
    $today = att_now($pdo)->format('Y-m-d');

    if (!$r) {
        require_once __DIR__ . '/../api/attendance.php';
        if ($h = attendance_holiday($pdo, $date)) { $add('holiday', "Public holiday: $h.", ['name' => $h]); $status = 'holiday'; }
        elseif (attendance_on_leave($pdo, $employeeId, $date)) { $add('on_leave', 'You were on approved leave.'); $status = 'on_leave'; }
        elseif (!att_is_workday($pdo, $shift, $date)) { $add('day_off', 'This is a day off in your schedule.'); $status = 'off'; }
        elseif ($date > $today) { $add('future', 'This day has not happened yet.'); $status = 'future'; }
        elseif ($date === $today) { $add('not_yet', 'You have not checked in yet today.'); $status = 'not_in'; }
        else { $add('no_record', 'No check-in was recorded on a working day, so it counts as absent.', [], 'bad'); $status = 'absent'; }
    } else {
        $late = (int)$r['late_minutes']; $early = (int)$r['early_leave_minutes']; $out = (int)$r['out_zone_minutes'];
        $worked = $r['hours_worked'] !== null ? (float)$r['hours_worked'] : null;
        $len = att_shift_len($shift);
        $flags = array_filter(explode(',', (string)$r['flags']));
        $in = $r['check_in'] ? substr($r['check_in'], 0, 5) : null;
        if (in_array('day_off_work', $flags, true)) {
            $add('day_off_work', 'You worked on a day off, so you are never counted late and the time is extra work.', [], 'good');
        } else {
            if ($in) {
                if ($late <= 0) $add('on_time', "You checked in at $in, before the shift started.", ['time' => $in], 'good');
                elseif ($late <= $grace) $add('late_within_grace', "You checked in at $in, $late min after the start. That is inside the $grace min allowance, so it still counts as on time.", ['time' => $in, 'late' => $late, 'grace' => $grace], 'good');
                else $add('late_over_grace', "You checked in at $in, $late min after the start. The allowance is $grace min, so you are late.", ['time' => $in, 'late' => $late, 'grace' => $grace], 'warn');
            }
            if ((int)$p['absent_late_minutes'] > 0 && $late >= (int)$p['absent_late_minutes']) $add('absent_late', "Arriving {$p['absent_late_minutes']} min or more after the start counts as absent.", ['limit' => (int)$p['absent_late_minutes']], 'bad');
            if ((int)$p['half_day_late_minutes'] > 0 && $late >= (int)$p['half_day_late_minutes']) $add('half_late', "Arriving {$p['half_day_late_minutes']} min or more after the start counts as a half day.", ['limit' => (int)$p['half_day_late_minutes']], 'bad');
            if ($r['check_out']) {
                $outT = substr($r['check_out'], 0, 5);
                if ($early > (int)$p['early_leave_grace_minutes']) $add('early_leave', "You left at $outT, $early min before the shift ended (allowance {$p['early_leave_grace_minutes']} min).", ['time' => $outT, 'early' => $early, 'grace' => (int)$p['early_leave_grace_minutes']], 'warn');
                else $add('left_on_time', "You checked out at $outT.", ['time' => $outT], 'good');
                if ((int)$p['half_day_early_minutes'] > 0 && $early >= (int)$p['half_day_early_minutes']) $add('half_early', "Leaving {$p['half_day_early_minutes']} min or more early counts as a half day.", ['limit' => (int)$p['half_day_early_minutes']], 'bad');
                if ($worked !== null && (int)$p['half_day_min_hours_pct'] > 0 && $worked * 60 < $len * (int)$p['half_day_min_hours_pct'] / 100) $add('half_hours', "You worked $worked h, less than {$p['half_day_min_hours_pct']}% of the shift, which counts as a half day.", ['hours' => $worked, 'pct' => (int)$p['half_day_min_hours_pct']], 'bad');
                if ($worked !== null && (int)$p['absent_min_hours_pct'] > 0 && $worked * 60 < $len * (int)$p['absent_min_hours_pct'] / 100) $add('absent_hours', "You worked $worked h, less than {$p['absent_min_hours_pct']}% of the shift, which counts as absent.", ['hours' => $worked, 'pct' => (int)$p['absent_min_hours_pct']], 'bad');
            } elseif (in_array('missed_checkout', $flags, true)) {
                $add('missed_checkout', 'You did not check out, so the day was closed automatically (' . $p['missed_checkout'] . ').', ['action' => $p['missed_checkout']], 'warn');
            }
            if ($out > 0) {
                $limit = (int)$p['out_zone_half_day_minutes'];
                $add('out_zone', "You were away from the workplace for $out min" . ($limit > 0 ? " (a half day starts at $limit min)." : '.'), ['minutes' => $out, 'limit' => $limit], $limit > 0 && $out >= $limit ? 'bad' : 'warn');
            }
        }
        if (!empty($r['security_flags'])) {
            foreach (explode(',', $r['security_flags']) as $f) if (isset(ATT_SECURITY_LABELS[$f])) $add('sec_' . $f, ATT_SECURITY_LABELS[$f] . '.', [], 'warn');
        }
        if (($r['source'] ?? 'mobile') !== 'mobile') $add('edited_by_hr', 'This record was entered or edited by HR.');
    }
    $label = ['present' => 'Present', 'late' => 'Late', 'half_day' => 'Half day', 'absent' => 'Absent', 'on_leave' => 'On leave', 'holiday' => 'Holiday', 'off' => 'Day off', 'future' => 'Upcoming', 'not_in' => 'Not in yet'][$status] ?? (string)$status;
    $add('result', "Result: $label.", ['status' => $status], in_array($status, ['absent', 'half_day'], true) ? 'bad' : ($status === 'late' ? 'warn' : 'good'));

    $pending = $pdo->prepare("SELECT COUNT(*) FROM requests WHERE company_id = ? AND employee_id = ? AND type = 'attendance_correction' AND status = 'pending' AND payload LIKE ?");
    $pending->execute([cid(), $employeeId, '%' . $date . '%']);
    $hasPending = (int)$pending->fetchColumn() > 0;
    $recent = $date <= $today && $date >= (new DateTime($today))->modify('-30 days')->format('Y-m-d');
    return [
        'date' => $date, 'employee_id' => $employeeId, 'status' => $status, 'reasons' => $reasons,
        'can_dispute' => $recent && !$hasPending && !in_array($status, ['future', 'holiday', 'off'], true),
        'dispute_pending' => $hasPending,
    ];
}
