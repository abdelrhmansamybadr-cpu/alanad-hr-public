<?php
/**
 * Smart reminders, generated lazily when a phone asks for its notifications (no cron job needed).
 *   reminder_checkin   – the shift started more than 10 minutes ago and nobody has checked in
 *   reminder_checkout  – the shift is over and the day is still open
 * Each is sent at most once per day, and never on holidays, leave days or days off.
 */
require_once __DIR__ . '/policy.php';
require_once __DIR__ . '/../api/attendance.php';

function reminders_sent(PDO $pdo, int $userId, string $type, string $date): bool {
    $s = $pdo->prepare("SELECT 1 FROM notifications WHERE user_id = ? AND company_id = ? AND type = ? AND data LIKE ? LIMIT 1");
    $s->execute([$userId, cid(), $type, '%"date":"' . $date . '"%']);
    return (bool)$s->fetchColumn();
}

/** Tell a colleague it is someone's birthday today (once a day, never about themselves). */
function reminders_birthdays(PDO $pdo, int $userId, int $ownEmployeeId, string $date): void {
    $s = $pdo->prepare(
        "SELECT id, first_name, last_name FROM employees
         WHERE company_id = ? AND status != 'inactive' AND id != ? AND birth_date IS NOT NULL
           AND DATE_FORMAT(birth_date, '%m-%d') = ?"
    );
    $s->execute([cid(), $ownEmployeeId, substr($date, 5)]);
    foreach ($s->fetchAll() as $e) {
        $key = $date . '#' . $e['id'];
        $c = $pdo->prepare("SELECT 1 FROM notifications WHERE user_id = ? AND company_id = ? AND type = 'birthday' AND data LIKE ? LIMIT 1");
        $c->execute([$userId, cid(), '%"key":"' . $key . '"%']);
        if ($c->fetchColumn()) continue;
        notify($pdo, cid(), $userId, 'birthday', 'Birthday today', "Today is {$e['first_name']} {$e['last_name']}'s birthday. Send your wishes!", ['date' => $date, 'key' => $key, 'employee_id' => (int)$e['id']]);
    }
}

function reminders_run(PDO $pdo): void {
    try {
        $eid = own_employee_id();
        if ($eid <= 0) return;
        reminders_birthdays($pdo, (int)me()['id'], $eid, att_now($pdo)->format('Y-m-d'));
        $pol = att_policy($pdo);
        if (array_key_exists('reminders', $pol) && !$pol['reminders']) return;

        $emp = att_employee_row($pdo, $eid);
        if (!$emp || ($emp['status'] ?? '') === 'inactive') return;

        $now   = att_now($pdo);
        $date  = $now->format('Y-m-d');
        $shift = att_shift($pdo, $emp);
        if (!att_is_workday($pdo, $shift, $date) || attendance_holiday($pdo, $date) || attendance_on_leave($pdo, $eid, $date)) return;

        $nowMin = (int)$now->format('H') * 60 + (int)$now->format('i');
        $start  = att_min($shift['start']);
        $end    = $start + att_shift_len($shift);
        if ($end > 1440) return;       // overnight shifts: skip, the auto-close handles them

        $a = $pdo->prepare("SELECT check_in, check_out FROM attendance WHERE employee_id = ? AND company_id = ? AND date = ? LIMIT 1");
        $a->execute([$eid, cid(), $date]);
        $rec = $a->fetch();
        $uid = (int)me()['id'];

        if (!$rec || !$rec['check_in']) {
            if ($nowMin >= $start + 10 && $nowMin < $end && !reminders_sent($pdo, $uid, 'reminder_checkin', $date)) {
                notify($pdo, cid(), $uid, 'reminder_checkin', "Don't forget to check in",
                    'Your shift started at ' . $shift['start'] . '. Open the app and check in so your day counts.', ['date' => $date]);
            }
        } elseif (!$rec['check_out']) {
            if ($nowMin >= $end && !reminders_sent($pdo, $uid, 'reminder_checkout', $date)) {
                notify($pdo, cid(), $uid, 'reminder_checkout', "Don't forget to check out",
                    'Your shift ended at ' . $shift['end'] . '. Check out before you leave.', ['date' => $date]);
            }
        }
    } catch (Throwable $e) {
        error_log('reminders: ' . $e->getMessage());     // never break the notification call
    }
}
