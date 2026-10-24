<?php
/**
 * "Ask Al Anad HR": a built-in helper that answers common questions from the caller's own records.
 * It is rule-based (keywords in English and Arabic), not a language model, so it never invents anything:
 * every answer comes straight from the database, and unknown questions get a list of what it can do.
 *
 *   POST /assistant   {question}   ->  {answer, intent, actions:[{label, route}], suggestions:[...]}
 *   GET  /assistant/suggestions    ->  [..] questions worth tapping, depending on the role
 */
require_once __DIR__ . '/leaves.php';
require_once __DIR__ . '/attendance.php';
require_once __DIR__ . '/../helpers/points.php';

function handle_assistant(string $path, string $method, array $body): void {
    $pdo = getDB();
    $sub = explode('/', $path)[1] ?? '';
    if ($method === 'GET' && $sub === 'suggestions') {
        json_response(['success' => true, 'data' => assistant_suggestions(false)]);
    }
    if ($method !== 'POST' || $sub !== '') error_response('Not found', 404);

    $q = trim((string)($body['question'] ?? ''));
    if ($q === '' || mb_strlen($q) > 300) error_response('Ask a short question', 422);
    $ar = (bool)preg_match('/\p{Arabic}/u', $q);
    $intent = assistant_intent(mb_strtolower($q));
    $res = assistant_answer($pdo, $intent, $ar);
    $res['intent'] = $intent;
    $res['suggestions'] = assistant_suggestions($ar);
    json_response(['success' => true, 'data' => $res]);
}

function assistant_suggestions(bool $ar): array {
    $hr = is_hr();
    $list = [
        ['How many leave days do I have left?', 'كم رصيد إجازاتي المتبقي؟'],
        ['Did I check in today?', 'هل سجلت حضوري اليوم؟'],
        ['When is the next holiday?', 'متى الإجازة الرسمية القادمة؟'],
        ['How are my points?', 'كيف نقاطي؟'],
        ['When is my next payslip?', 'ما آخر قسيمة راتب؟'],
    ];
    if ($hr) {
        $list = [
            ['Who is absent today?', 'من الغائب اليوم؟'],
            ['Who is on leave today?', 'من في إجازة اليوم؟'],
            ['What is waiting for my approval?', 'ما الذي ينتظر موافقتي؟'],
            ['How many employees do we have?', 'كم عدد الموظفين؟'],
            ['Who is still onboarding?', 'من لا يزال في التهيئة؟'],
        ];
    }
    return array_map(fn($p) => $ar ? $p[1] : $p[0], $list);
}

/** Pick the topic from keywords (English and Arabic). The first match wins, most specific first. */
function assistant_intent(string $q): string {
    $rules = [
        'hr_absent'     => '/(who|من).*(absent|غائب|غياب)|absent today|الغائب/u',
        'hr_on_leave'   => '/(who|من).*(leave|إجازة|اجازة)|on leave today/u',
        'hr_pending'    => '/(approval|pending|waiting|موافقة|معلق|ينتظر)/u',
        'hr_headcount'  => '/(how many|عدد|كم).*(employee|staff|people|موظف)|headcount/u',
        'hr_onboarding' => '/(onboard|تهيئة)/u',
        'leave_balance' => '/(leave|vacation|days off|إجازة|اجازة|رصيد)/u',
        'attendance'    => '/(check.?in|checked in|attendance|حضور|حضرت|سجلت|بصمة|انصراف)/u',
        'holiday'       => '/(holiday|عطلة|عطله|إجازة رسمية)/u',
        'points'        => '/(point|level|streak|reward|نقاط|نقطة|مستوى|مكافأ)/u',
        'payslip'       => '/(pay|salary|راتب|قسيمة|مرتب)/u',
        'shift'         => '/(shift|hours|schedule|working time|وردية|دوام|ساعات|مواعيد)/u',
        'manager'       => '/(manager|boss|مدير|رئيسي)/u',
        'onboarding_me' => '/(getting started|checklist|ابدأ|خطوات)/u',
        'late'          => '/(late|تأخر|متأخر)/u',
    ];
    foreach ($rules as $intent => $re) if (preg_match($re, $q)) return $intent;
    return 'help';
}

function assistant_answer(PDO $pdo, string $intent, bool $ar): array {
    $t = fn(string $en, string $arText) => $ar ? $arText : $en;
    $eid = own_employee_id();
    $hr = is_hr();
    $act = fn(string $en, string $arText, string $route) => ['label' => $t($en, $arText), 'route' => $route];
    $today = att_now($pdo)->format('Y-m-d');

    // ---- questions about the company (HR only)
    if (str_starts_with($intent, 'hr_')) {
        if (!$hr) return ['answer' => $t('That information is for HR.', 'هذه المعلومة متاحة للموارد البشرية فقط.'), 'actions' => []];
        switch ($intent) {
            case 'hr_headcount':
                $n = $pdo->prepare("SELECT COUNT(*) FROM employees WHERE company_id = ? AND status != 'inactive'");
                $n->execute([cid()]);
                return ['answer' => $t('You have ' . $n->fetchColumn() . ' active employees.', 'لديك ' . $n->fetchColumn() . ' موظفاً نشطاً.'), 'actions' => [$act('Open people', 'فتح الموظفين', '/h/people')]];
            case 'hr_absent':
                $s = $pdo->prepare(
                    "SELECT CONCAT(e.first_name,' ',e.last_name) FROM attendance a JOIN employees e ON e.id = a.employee_id
                     WHERE a.company_id = ? AND a.date = ? AND a.status = 'absent' ORDER BY e.first_name LIMIT 15"
                );
                $s->execute([cid(), $today]);
                $names = $s->fetchAll(PDO::FETCH_COLUMN);
                $txt = $names ? implode($ar ? '، ' : ', ', $names) : '';
                return ['answer' => $names ? $t("Marked absent today: $txt.", "الغائبون اليوم: $txt.") : $t('Nobody is marked absent today so far.', 'لا أحد مسجل غائباً حتى الآن.'),
                        'actions' => [$act('Open attendance board', 'فتح لوحة الحضور', '/h/attendance')]];
            case 'hr_on_leave':
                $s = $pdo->prepare(
                    "SELECT CONCAT(e.first_name,' ',e.last_name) FROM leaves l JOIN employees e ON e.id = l.employee_id
                     WHERE l.company_id = ? AND l.status = 'approved' AND ? BETWEEN l.start_date AND l.end_date ORDER BY e.first_name LIMIT 15"
                );
                $s->execute([cid(), $today]);
                $names = $s->fetchAll(PDO::FETCH_COLUMN);
                $txt = $names ? implode($ar ? '، ' : ', ', $names) : '';
                return ['answer' => $names ? $t("On leave today: $txt.", "في إجازة اليوم: $txt.") : $t('Nobody is on leave today.', 'لا أحد في إجازة اليوم.'), 'actions' => []];
            case 'hr_pending':
                $a = $pdo->prepare("SELECT COUNT(*) FROM leaves WHERE company_id = ? AND status = 'pending'");
                $a->execute([cid()]);
                $b = $pdo->prepare("SELECT COUNT(*) FROM requests WHERE company_id = ? AND status = 'pending'");
                $b->execute([cid()]);
                $n = (int)$a->fetchColumn() + (int)$b->fetchColumn();
                return ['answer' => $n ? $t("$n requests are waiting for approval.", "هناك $n طلبات تنتظر الموافقة.") : $t('Nothing is waiting for approval.', 'لا توجد طلبات معلقة.'),
                        'actions' => $n ? [$act('Review now', 'مراجعة الآن', '/h/approvals')] : []];
            case 'hr_onboarding':
                $s = $pdo->prepare(
                    "SELECT CONCAT(e.first_name,' ',e.last_name) AS n, SUM(t.done) AS d, COUNT(*) AS c FROM onboarding_tasks t JOIN employees e ON e.id = t.employee_id
                     WHERE t.company_id = ? AND e.status != 'inactive' GROUP BY e.id HAVING d < c ORDER BY n LIMIT 10"
                );
                $s->execute([cid()]);
                $rows = $s->fetchAll();
                $txt = implode($ar ? '، ' : ', ', array_map(fn($r) => "{$r['n']} ({$r['d']}/{$r['c']})", $rows));
                return ['answer' => $rows ? $t("Still onboarding: $txt.", "لا يزالون في التهيئة: $txt.") : $t('Everyone has finished onboarding.', 'أنهى الجميع التهيئة.'),
                        'actions' => [$act('Open onboarding', 'فتح التهيئة', '/h/onboarding')]];
        }
    }

    // ---- questions about me
    if ($eid <= 0) return ['answer' => $t('Your account is not linked to an employee record, so I cannot look that up.', 'حسابك غير مرتبط بسجل موظف، لذلك لا أستطيع البحث عن ذلك.'), 'actions' => []];

    switch ($intent) {
        case 'leave_balance':
            $rows = array_filter(leaves_balance($pdo, $eid, (int)substr($today, 0, 4)), fn($b) => $b['remaining'] !== null);
            if (!$rows) return ['answer' => $t('Your leave types have no fixed yearly limit.', 'أنواع إجازاتك بلا حد سنوي ثابت.'), 'actions' => [$act('Request leave', 'طلب إجازة', '/e/requests')]];
            $txt = implode($ar ? '، ' : ', ', array_map(fn($b) => $b['name'] . ': ' . $b['remaining'] . '/' . $b['total'], $rows));
            return ['answer' => $t("Leave left this year: $txt.", "المتبقي من إجازاتك هذا العام: $txt."), 'actions' => [$act('Request leave', 'طلب إجازة', '/e/requests')]];

        case 'attendance':
            $s = $pdo->prepare("SELECT check_in, check_out, status FROM attendance WHERE company_id = ? AND employee_id = ? AND date = ? LIMIT 1");
            $s->execute([cid(), $eid, $today]);
            $r = $s->fetch();
            if (!$r || !$r['check_in']) return ['answer' => $t("You have not checked in today.", 'لم تسجل حضورك اليوم.'), 'actions' => [$act('Check in', 'تسجيل الحضور', '/e/time')]];
            $in = substr($r['check_in'], 0, 5);
            if (!$r['check_out']) return ['answer' => $t("You checked in at $in and have not checked out yet. Status: {$r['status']}.", "سجلت حضورك الساعة $in ولم تسجل الانصراف بعد. الحالة: {$r['status']}."), 'actions' => [$act('Check out', 'تسجيل الانصراف', '/e/time')]];
            return ['answer' => $t("You worked {$in} to " . substr($r['check_out'], 0, 5) . ". Status: {$r['status']}.", "عملت من $in إلى " . substr($r['check_out'], 0, 5) . ". الحالة: {$r['status']}."), 'actions' => []];

        case 'late':
            $s = $pdo->prepare("SELECT status, COUNT(*) FROM attendance WHERE company_id = ? AND employee_id = ? AND date >= ? GROUP BY status");
            $s->execute([cid(), $eid, substr($today, 0, 8) . '01']);
            $c = $s->fetchAll(PDO::FETCH_KEY_PAIR);
            $late = (int)($c['late'] ?? 0); $half = (int)($c['half_day'] ?? 0); $abs = (int)($c['absent'] ?? 0);
            return ['answer' => $t("This month: $late late, $half half days, $abs absences.", "هذا الشهر: $late تأخير، $half نصف يوم، $abs غياب."), 'actions' => [$act('See my time', 'عرض حضوري', '/e/time')]];

        case 'holiday':
            $s = $pdo->prepare("SELECT name, date FROM holidays WHERE company_id = ? AND date >= ? ORDER BY date LIMIT 1");
            $s->execute([cid(), $today]);
            $h = $s->fetch();
            if (!$h) return ['answer' => $t('No upcoming holidays are set.', 'لا توجد عطلات قادمة مسجلة.'), 'actions' => []];
            $days = (int)(new DateTime($today))->diff(new DateTime($h['date']))->days;
            return ['answer' => $t("Next holiday: {$h['name']} on {$h['date']} ($days days away).", "العطلة القادمة: {$h['name']} بتاريخ {$h['date']} (بعد $days يوماً)."), 'actions' => [$act('All holidays', 'كل العطلات', '/holidays')]];

        case 'points':
            $p = points_summary($pdo, $eid);
            if (empty($p['enabled'])) return ['answer' => $t('Reward points are turned off in your company.', 'نقاط المكافآت متوقفة في شركتك.'), 'actions' => []];
            $g = $p['net']['green']; $r = $p['net']['red']; $b = $p['net']['black'];
            return ['answer' => $t("Level {$p['level']} ({$p['level_name']}), streak {$p['streak']}/{$p['streak_target']} green days. Points: $g green, $r red, $b black.",
                                   "المستوى {$p['level']} ({$p['level_name']})، سلسلة {$p['streak']}/{$p['streak_target']} يوماً أخضر. النقاط: $g خضراء، $r حمراء، $b سوداء."),
                    'actions' => [$act('Open rewards', 'فتح المكافآت', '/rewards')]];

        case 'payslip':
            $s = $pdo->prepare("SELECT month, year, net_pay, status FROM payroll WHERE employee_id = ? ORDER BY year DESC, month DESC LIMIT 1");
            $s->execute([$eid]);
            $p = $s->fetch();
            if (!$p) return ['answer' => $t('No payslip has been issued for you yet.', 'لم تصدر لك قسيمة راتب بعد.'), 'actions' => []];
            return ['answer' => $t("Your latest payslip is {$p['month']}/{$p['year']}: net {$p['net_pay']} ({$p['status']}).", "آخر قسيمة لك {$p['month']}/{$p['year']}: الصافي {$p['net_pay']} ({$p['status']})."), 'actions' => [$act('Open payslips', 'فتح القسائم', '/payslips')]];

        case 'shift':
            $e = att_employee_row($pdo, $eid);
            $sh = att_shift($pdo, $e);
            return ['answer' => $t("Your hours are {$sh['start']} to {$sh['end']}" . ($sh['name'] ? " ({$sh['name']})" : '') . '.', "ساعات عملك من {$sh['start']} إلى {$sh['end']}" . ($sh['name'] ? " ({$sh['name']})" : '') . '.'), 'actions' => []];

        case 'manager':
            $s = $pdo->prepare("SELECT CONCAT(m.first_name,' ',m.last_name) FROM employees e JOIN employees m ON m.id = e.manager_id WHERE e.id = ?");
            $s->execute([$eid]);
            $m = $s->fetchColumn();
            return ['answer' => $m ? $t("Your manager is $m.", "مديرك هو $m.") : $t('No manager is set for you.', 'لا يوجد مدير محدد لك.'), 'actions' => []];

        case 'onboarding_me':
            $s = $pdo->prepare("SELECT COUNT(*), COALESCE(SUM(done),0) FROM onboarding_tasks WHERE company_id = ? AND employee_id = ?");
            $s->execute([cid(), $eid]);
            [$c, $d] = $s->fetch(PDO::FETCH_NUM);
            if (!$c) return ['answer' => $t('You have no onboarding checklist.', 'ليس لديك قائمة تهيئة.'), 'actions' => []];
            return ['answer' => $t("You have finished $d of $c getting-started steps.", "أنهيت $d من $c خطوات البداية."), 'actions' => [$act('Open checklist', 'فتح القائمة', '/onboarding')]];
    }

    return [
        'answer'  => $t("I can answer about your leave balance, attendance, holidays, points, payslip, shift and manager" . ($hr ? ', and about absences, approvals and headcount' : '') . '. Try one of the suggestions.',
                        'أستطيع الإجابة عن رصيد الإجازات والحضور والعطلات والنقاط والراتب والوردية والمدير' . ($hr ? ' وعن الغياب والموافقات وعدد الموظفين' : '') . '. جرّب أحد الاقتراحات.'),
        'actions' => [],
    ];
}
