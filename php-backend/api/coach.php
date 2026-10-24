<?php
/**
 * Manager coach (feature `manager_coach`): plain-words advice for this week, from real patterns in the data.
 * Rule-based on purpose (no language model): every tip names the rule that fired and the numbers behind it,
 * so a manager can check it and nothing is invented.
 *
 *   GET /coach/weekly     tips for the caller's people: HR -> the whole company, a team lead -> their team.
 *                         Anybody else gets 403.
 *
 * Rules: lateness_rising, absences, overtime_heavy, approvals_waiting, probation_ending, no_recognition, no_break, anniversary.
 */
function handle_coach(string $path, string $method, array $body): void {
    $pdo = getDB();
    $sub = explode('/', $path)[1] ?? '';
    if ($sub !== 'weekly') error_response('Endpoint not found: coach/' . $sub, 404);
    if ($method !== 'GET') error_response('Method not allowed', 405);
    if (!is_hr() && !has_direct_reports($pdo)) error_response('Forbidden. The coach is for managers.', 403);
    json_response(['success' => true, 'data' => coach_weekly($pdo)]);
}

function coach_tip(string $code, string $sev, ?array $emp, string $titleEn, string $titleAr, string $actEn, string $actAr, array $data = []): array {
    return ['code' => $code, 'severity' => $sev, 'employee_id' => $emp['id'] ?? null,
            'employee_name' => $emp ? trim($emp['first_name'] . ' ' . $emp['last_name']) : null,
            'title_en' => $titleEn, 'title_ar' => $titleAr, 'action_en' => $actEn, 'action_ar' => $actAr, 'data' => $data];
}

function coach_weekly(PDO $pdo): array {
    $now = att_now($pdo);
    $today = $now->format('Y-m-d');
    $d = fn(int $back) => (clone $now)->modify("-$back days")->format('Y-m-d');
    $company = is_hr();

    // the people in scope
    if ($company) {
        $q = $pdo->prepare("SELECT id, first_name, last_name, start_date, birth_date FROM employees WHERE company_id = ? AND status != 'inactive'");
        $q->execute([cid()]);
    } else {
        $q = $pdo->prepare("SELECT id, first_name, last_name, start_date, birth_date FROM employees WHERE company_id = ? AND manager_id = ? AND status != 'inactive'");
        $q->execute([cid(), own_employee_id()]);
    }
    $people = [];
    foreach ($q->fetchAll() as $e) $people[(int)$e['id']] = $e;
    $tips = [];
    if (!$people) return coach_wrap($company, $today, $tips, 0);
    $in = implode(',', array_keys($people));

    // attendance: last 14 days vs the 14 before
    $a = $pdo->query("SELECT employee_id,
            SUM(date >= '{$d(13)}' AND status = 'late') AS late_now,
            SUM(date < '{$d(13)}' AND status = 'late') AS late_before,
            SUM(date >= '{$d(13)}' AND status = 'absent') AS absent_now,
            SUM(date >= '{$d(13)}' AND status = 'half_day') AS half_now,
            SUM(CASE WHEN date >= '{$d(13)}' THEN overtime_minutes ELSE 0 END) AS ot_now
        FROM attendance WHERE company_id = " . cid() . " AND employee_id IN ($in) AND date >= '{$d(27)}' AND date <= '$today' GROUP BY employee_id");
    foreach ($a->fetchAll() as $r) {
        $e = $people[(int)$r['employee_id']] ?? null;
        if (!$e) continue;
        $now_ = (int)$r['late_now']; $before = (int)$r['late_before'];
        if ($now_ >= 3 && $now_ >= $before + 2) {
            $tips[] = coach_tip('lateness_rising', $now_ >= 5 ? 'high' : 'medium', $e,
                "Lateness is rising: $now_ late days in 2 weeks (was $before)", "التأخير يزيد: $now_ أيام تأخير في أسبوعين (كان $before)",
                'Talk privately and ask what changed (transport, shift, personal). Agree one small change.', 'تكلم معه على انفراد واسأله ما الذي تغيّر (المواصلات أو الوردية أو ظروف شخصية) واتفقوا على تغيير صغير واحد.',
                ['late_days' => $now_, 'previous' => $before]);
        }
        $ab = (int)$r['absent_now'] + (int)$r['half_now'];
        if ((int)$r['absent_now'] >= 2 || $ab >= 3) {
            $tips[] = coach_tip('absences', (int)$r['absent_now'] >= 3 ? 'high' : 'medium', $e,
                "{$r['absent_now']} absent days and {$r['half_now']} half days in 2 weeks", "{$r['absent_now']} أيام غياب و{$r['half_now']} نصف يوم في أسبوعين",
                'Check in on how they are. If it is health or family, point them to the right leave type.', 'اطمئن عليه. إذا كان السبب صحياً أو عائلياً فوجّهه لنوع الإجازة المناسب.',
                ['absent' => (int)$r['absent_now'], 'half_days' => (int)$r['half_now']]);
        }
        $otH = round((int)$r['ot_now'] / 60, 1);
        if ($otH >= 20) {
            $tips[] = coach_tip('overtime_heavy', $otH >= 30 ? 'high' : 'medium', $e,
                "$otH overtime hours in 2 weeks", "$otH ساعة عمل إضافي في أسبوعين",
                'Look at the workload: can a task move to someone else this week? Give a rest day after the push.', 'راجع حجم العمل: هل يمكن نقل مهمة لغيره هذا الأسبوع؟ وامنحه يوم راحة بعد الضغط.',
                ['overtime_hours' => $otH]);
        }
    }

    // approvals the caller has left waiting
    $wait = [];
    $p = $pdo->query("SELECT l.id, l.employee_id, TIMESTAMPDIFF(HOUR, l.created_at, UTC_TIMESTAMP()) AS hrs FROM leaves l
        WHERE l.company_id = " . cid() . " AND l.status = 'pending' AND l.employee_id IN ($in) AND l.created_at < (UTC_TIMESTAMP() - INTERVAL 48 HOUR)");
    foreach ($p->fetchAll() as $r) $wait[] = [(int)$r['employee_id'], (int)$r['hrs'], 'leave'];
    $p = $pdo->query("SELECT r.id, r.employee_id, TIMESTAMPDIFF(HOUR, r.created_at, UTC_TIMESTAMP()) AS hrs FROM requests r
        WHERE r.company_id = " . cid() . " AND r.status = 'pending' AND r.employee_id IN ($in) AND r.created_at < (UTC_TIMESTAMP() - INTERVAL 48 HOUR)");
    foreach ($p->fetchAll() as $r) $wait[] = [(int)$r['employee_id'], (int)$r['hrs'], 'request'];
    if ($wait) {
        $oldest = max(array_column($wait, 1));
        $n = count($wait);
        $tips[] = coach_tip('approvals_waiting', $oldest >= 96 ? 'high' : 'medium', null,
            "$n request" . ($n > 1 ? 's are' : ' is') . " waiting more than 2 days (oldest: " . intdiv($oldest, 24) . " days)",
            "$n طلب ينتظر أكثر من يومين (الأقدم: " . intdiv($oldest, 24) . " أيام)",
            'Answer them today. A fast "no" with a reason is better than a slow "yes".', 'ردّ عليها اليوم. "لا" سريعة مع السبب أفضل من "نعم" متأخرة.',
            ['waiting' => $n, 'oldest_hours' => $oldest]);
    }

    // probation ending in the next 14 days (3 months after the start date)
    foreach ($people as $e) {
        if (!$e['start_date']) continue;
        $end = (new DateTime($e['start_date']))->modify('+3 months')->format('Y-m-d');
        if ($end >= $today && $end <= (clone $now)->modify('+14 days')->format('Y-m-d')) {
            $tips[] = coach_tip('probation_ending', 'medium', $e,
                "Probation ends on $end", "تنتهي فترة التجربة في $end",
                'Book the probation review now: what went well, what to improve, and confirm or extend.', 'حدّد موعد تقييم فترة التجربة الآن: ما الذي سار جيداً وما الذي يتحسن، ثم التثبيت أو التمديد.',
                ['ends' => $end]);
        }
    }

    // nobody recognised for 30 days (only people who have worked here more than a month)
    $k = $pdo->query("SELECT DISTINCT to_employee_id FROM kudos WHERE company_id = " . cid() . " AND created_at >= (UTC_TIMESTAMP() - INTERVAL 30 DAY)");
    $kudos = array_map('intval', $k->fetchAll(PDO::FETCH_COLUMN));
    $quiet = [];
    foreach ($people as $e) {
        if ($e['start_date'] && $e['start_date'] > $d(30)) continue;
        if (!in_array((int)$e['id'], $kudos, true)) $quiet[] = $e;
    }
    if (count($quiet) >= 1 && (count($quiet) >= 2 || count($people) <= 3)) {
        $names = implode(', ', array_map(fn($e) => $e['first_name'], array_slice($quiet, 0, 5)));
        $tips[] = coach_tip('no_recognition', 'low', null,
            count($quiet) . " people got no recognition in 30 days: $names", count($quiet) . " أشخاص لم يحصلوا على تقدير خلال 30 يوماً: $names",
            'Give two real, specific thank-yous this week from the Kudos screen.', 'قدّم شكرين حقيقيين ومحددين هذا الأسبوع من شاشة التقدير.',
            ['count' => count($quiet), 'employee_ids' => array_map(fn($e) => (int)$e['id'], $quiet)]);
    }

    // no break in 6 months
    $l = $pdo->query("SELECT DISTINCT employee_id FROM leaves WHERE company_id = " . cid() . " AND status = 'approved' AND end_date >= '{$d(180)}'");
    $rested = array_map('intval', $l->fetchAll(PDO::FETCH_COLUMN));
    foreach ($people as $e) {
        if (!$e['start_date'] || $e['start_date'] > $d(180)) continue;
        if (!in_array((int)$e['id'], $rested, true)) {
            $tips[] = coach_tip('no_break', 'low', $e, 'No leave taken in 6 months', 'لم يأخذ أي إجازة منذ 6 شهور',
                'Encourage a few days off before burnout. Offer to plan cover together.', 'شجّعه على أخذ بضعة أيام قبل الإرهاق، واعرض أن تخططوا للتغطية معاً.', []);
        }
    }

    // work anniversaries this week
    foreach ($people as $e) {
        if (!$e['start_date']) continue;
        $ann = (new DateTime($e['start_date']))->format('m-d');
        for ($i = 0; $i <= 7; $i++) {
            if ((clone $now)->modify("+$i days")->format('m-d') === $ann) {
                $years = (int)$now->format('Y') - (int)substr($e['start_date'], 0, 4);
                if ($years >= 1) $tips[] = coach_tip('anniversary', 'low', $e, "$years-year work anniversary this week", "ذكرى $years سنة في العمل هذا الأسبوع",
                    'Say it in person or in the team chat. Remembering costs nothing.', 'قلها له شخصياً أو في مجموعة الفريق. التذكّر لا يكلّف شيئاً.', ['years' => $years]);
                break;
            }
        }
    }

    $rank = ['high' => 0, 'medium' => 1, 'low' => 2];
    usort($tips, fn($a, $b) => $rank[$a['severity']] <=> $rank[$b['severity']]);
    return coach_wrap($company, $today, $tips, count($people));
}

function coach_wrap(bool $company, string $today, array $tips, int $headcount): array {
    $sum = ['high' => 0, 'medium' => 0, 'low' => 0];
    foreach ($tips as $t) $sum[$t['severity']]++;
    return ['scope' => $company ? 'company' : 'team', 'date' => $today, 'headcount' => $headcount, 'summary' => $sum, 'tips' => $tips];
}
