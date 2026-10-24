<?php
/**
 * Real Arabic pack (feature `arabic_pack`): documents in proper Arabic, amounts in words, and Arabic voice commands.
 *
 *   GET  /arabic/letter-link?type=employment|salary|experience[&employee_id=][&digits=ar]   -> {url, expires_in}
 *        a signed 10-minute link to a printable Arabic letter (public route /arabic-view?t=...), like the payslip link
 *   GET  /arabic/payslip/{payrollId}       -> {url}  the same signed payslip page, always in Arabic
 *   GET  /arabic/words?amount=1250.5&currency=EGP|SAR      the amount written in Arabic words
 *   POST /arabic/voice   {text}            understands an Arabic sentence (Egyptian, Gulf and standard) and answers
 *
 * Voice never changes anything by itself: check-in / check-out come back as an action the app must CONFIRM
 * (they also need the phone's location), and questions are answered from the caller's own records.
 */
require_once __DIR__ . '/../helpers/labor_law.php';
require_once __DIR__ . '/../helpers/payroll_extra.php';
require_once __DIR__ . '/payroll.php';                     // payroll_fetch() for the payslip link

function handle_arabic(string $path, string $method, array $body): void {
    $pdo = getDB();
    $seg = explode('/', $path);
    $a = $seg[1] ?? '';
    if ($a === 'letter-link') { if ($method !== 'GET') error_response('Method not allowed', 405); arabic_letter_link($pdo); }
    if ($a === 'payslip' && ctype_digit((string)($seg[2] ?? ''))) {
        if ($method !== 'GET') error_response('Method not allowed', 405);
        $_GET['lang'] = 'ar';
        payroll_payslip_link((int)$seg[2], $pdo);
    }
    if ($a === 'words') { if ($method !== 'GET') error_response('Method not allowed', 405); arabic_words_api(); }
    if ($a === 'voice') { if ($method !== 'POST') error_response('Method not allowed', 405); arabic_voice($pdo, $body); }
    error_response('Endpoint not found: arabic/' . $a, 404);
}

// ------------------------------------------------------------------ numbers in Arabic

function arabic_digits(string $s): string { return strtr($s, ['0' => '٠', '1' => '١', '2' => '٢', '3' => '٣', '4' => '٤', '5' => '٥', '6' => '٦', '7' => '٧', '8' => '٨', '9' => '٩', '.' => '٫']); }

/** 0..999 in Arabic words (masculine, as used with currency units like جنيه / ريال). */
function arabic_below_1000(int $n): string {
    $ones = ['', 'واحد', 'اثنان', 'ثلاثة', 'أربعة', 'خمسة', 'ستة', 'سبعة', 'ثمانية', 'تسعة', 'عشرة', 'أحد عشر', 'اثنا عشر', 'ثلاثة عشر', 'أربعة عشر', 'خمسة عشر', 'ستة عشر', 'سبعة عشر', 'ثمانية عشر', 'تسعة عشر'];
    $tens = ['', '', 'عشرون', 'ثلاثون', 'أربعون', 'خمسون', 'ستون', 'سبعون', 'ثمانون', 'تسعون'];
    $hund = ['', 'مائة', 'مائتان', 'ثلاثمائة', 'أربعمائة', 'خمسمائة', 'ستمائة', 'سبعمائة', 'ثمانمائة', 'تسعمائة'];
    $parts = [];
    if ($n >= 100) { $parts[] = $hund[intdiv($n, 100)]; $n %= 100; }
    if ($n > 0) {
        if ($n < 20) $parts[] = $ones[$n];
        else { $u = $n % 10; $t = intdiv($n, 10); $parts[] = ($u ? $ones[$u] . ' و' : '') . $tens[$t]; }
    }
    return implode(' و', $parts);
}

/** Whole number in Arabic words (up to 999,999,999,999). */
function arabic_words_int(int $n): string {
    if ($n === 0) return 'صفر';
    $scales = [[1000000000, 'مليار', 'ملياران', 'مليارات'], [1000000, 'مليون', 'مليونان', 'ملايين'], [1000, 'ألف', 'ألفان', 'آلاف']];
    $parts = [];
    foreach ($scales as [$v, $one, $two, $few]) {
        if ($n >= $v) {
            $q = intdiv($n, $v); $n %= $v;
            if ($q === 1) $parts[] = $one;
            elseif ($q === 2) $parts[] = $two;
            elseif ($q <= 10) $parts[] = arabic_below_1000($q) . ' ' . $few;
            else $parts[] = arabic_below_1000($q) . ' ' . $one;
        }
    }
    if ($n > 0) $parts[] = arabic_below_1000($n);
    return implode(' و', $parts);
}

/** "ألف ومائتان وخمسون جنيهاً وخمسون قرشاً فقط لا غير" */
function arabic_money_words(float $amount, string $currency): string {
    $units = ['EGP' => ['جنيه', 'جنيهان', 'جنيهات', 'جنيهاً', 'قرش', 'قرشان', 'قروش', 'قرشاً'], 'SAR' => ['ريال', 'ريالان', 'ريالات', 'ريالاً', 'هللة', 'هللتان', 'هللات', 'هللة']];
    $u = $units[strtoupper($currency)] ?? $units['EGP'];
    $amount = round($amount, 2);
    $whole = (int)floor($amount); $sub = (int)round(($amount - $whole) * 100);
    $word = function (int $n, array $f) {          // [singular, dual, few(3-10), many(11+ accusative)]
        if ($n === 1) return $f[0];
        if ($n === 2) return $f[1];
        if ($n >= 3 && $n <= 10) return arabic_words_int($n) . ' ' . $f[2];
        return arabic_words_int($n) . ' ' . $f[3];
    };
    $txt = $whole > 0 || $sub === 0 ? $word($whole, array_slice($u, 0, 4)) : '';
    if ($whole === 0 && $sub === 0) $txt = 'صفر ' . $u[3];
    if ($sub > 0) $txt .= ($txt ? ' و' : '') . $word($sub, array_slice($u, 4, 4));
    return $txt . ' فقط لا غير';
}

function arabic_words_api(): void {
    $amount = $_GET['amount'] ?? null;
    if (!is_numeric($amount) || (float)$amount < 0 || (float)$amount > 999999999999) error_response('amount must be a number between 0 and 999,999,999,999', 422);
    $cur = strtoupper((string)($_GET['currency'] ?? 'EGP'));
    if (!in_array($cur, ['EGP', 'SAR'], true)) error_response('currency must be EGP or SAR', 422);
    json_response(['success' => true, 'data' => ['amount' => (float)$amount, 'currency' => $cur, 'words' => arabic_money_words((float)$amount, $cur)]]);
}

// ------------------------------------------------------------------ letters

function arabic_letter_types(): array { return ['employment' => 'شهادة إثبات عمل', 'salary' => 'شهادة راتب', 'experience' => 'شهادة خبرة']; }

function arabic_letter_token(PDO $pdo, string $type, int $eid, int $companyId, bool $arDigits, int $ttl = 600): string {
    $payload = 'L.' . $type . '.' . $eid . '.' . $companyId . '.' . ($arDigits ? 1 : 0) . '.' . (time() + $ttl);
    return rtrim(strtr(base64_encode($payload), '+/', '-_'), '=') . '.' . hash_hmac('sha256', $payload, payslip_secret($pdo));
}

/** [type, employeeId, companyId, arDigits] for a valid token, else null. */
function arabic_letter_token_check(PDO $pdo, string $token): ?array {
    $parts = explode('.', $token, 2);
    if (count($parts) !== 2) return null;
    $payload = base64_decode(strtr($parts[0], '-_', '+/'), true);
    if ($payload === false || !preg_match('/^L\.(employment|salary|experience)\.(\d+)\.(\d+)\.([01])\.(\d+)$/', $payload, $m)) return null;
    if (!hash_equals(hash_hmac('sha256', $payload, payslip_secret($pdo)), $parts[1])) return null;
    if ((int)$m[5] < time()) return null;
    return [$m[1], (int)$m[2], (int)$m[3], $m[4] === '1'];
}

function arabic_letter_link(PDO $pdo): void {
    $type = (string)($_GET['type'] ?? '');
    if (!isset(arabic_letter_types()[$type])) error_response('type must be employment, salary or experience', 422);
    $eid = is_hr() && !empty($_GET['employee_id']) ? (int)$_GET['employee_id'] : own_employee_id();
    if ($eid <= 0) error_response('Choose an employee', 422);
    if (!employee_in_company($pdo, $eid)) error_response('Employee not found', 404);
    if (!is_hr() && $eid !== own_employee_id()) error_response('Forbidden. Insufficient permissions.', 403);
    audit($pdo, 'letter', 'employee', $eid, ['type' => $type]);
    $base = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off' ? 'https://' : 'http://') . ($_SERVER['HTTP_HOST'] ?? 'localhost');
    $tok = arabic_letter_token($pdo, $type, $eid, cid(), ($_GET['digits'] ?? '') === 'ar');
    json_response(['success' => true, 'data' => ['url' => $base . '/arabic-view?t=' . $tok, 'expires_in' => 600]]);
}

/** Public route /arabic-view?t=TOKEN: the printable Arabic letter. */
function handle_arabic_view(): void {
    $pdo = getDB();
    $chk = arabic_letter_token_check($pdo, (string)($_GET['t'] ?? ''));
    header('Content-Type: text/html; charset=utf-8');
    header('Cache-Control: no-store');
    if (!$chk) { http_response_code(403); echo '<!doctype html><meta charset="utf-8"><body dir="rtl" style="font-family:sans-serif;padding:40px">انتهت صلاحية الرابط. افتح الشهادة من التطبيق مرة أخرى.</body>'; exit; }
    [$type, $eid, $companyId, $arDigits] = $chk;
    if (!feature_enabled($pdo, 'arabic_pack', $companyId)) { http_response_code(403); echo '<!doctype html><meta charset="utf-8"><body dir="rtl" style="font-family:sans-serif;padding:40px">هذه الخدمة غير مفعّلة لشركتك.</body>'; exit; }
    $co = company_get($pdo, $companyId);
    $s = $pdo->prepare("SELECT * FROM employees WHERE id = ? AND company_id = ?");
    $s->execute([$eid, $companyId]);
    $e = $s->fetch();
    if (!$co || !$e) { http_response_code(404); echo 'not found'; exit; }
    echo arabic_letter_html($co, $e, $type, $arDigits);
    exit;
}

function arabic_letter_html(array $co, array $e, string $type, bool $arDigits): string {
    $h = fn($v) => htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8');
    $num = fn($v) => $arDigits ? arabic_digits((string)$v) : (string)$v;
    $date = function (?string $d) use ($num) {
        if (!$d) return '';
        $hj = law_hijri($d);
        $mon = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'][(int)substr($d, 5, 2) - 1];
        return $num((int)substr($d, 8, 2)) . ' ' . $mon . ' ' . $num(substr($d, 0, 4)) . ' م (' . $num($hj['day']) . ' ' . $hj['month_name_ar'] . ' ' . $num($hj['year']) . ' هـ)';
    };
    $name = trim($e['first_name'] . ' ' . $e['last_name']);
    $pos = $e['position'] ?: 'موظف';
    $title = arabic_letter_types()[$type];
    $today = gmdate('Y-m-d');
    $cur = strtoupper((string)($co['currency'] ?: 'EGP'));
    $curName = ['EGP' => 'جنيه مصري', 'SAR' => 'ريال سعودي'][$cur] ?? $cur;
    $emp = $e['status'] === 'inactive' ? 'كان يعمل' : 'يعمل';
    $body = '';
    if ($type === 'employment') {
        $body = "تشهد شركة <b>{$h($co['name'])}</b> بأن السيد/السيدة <b>{$h($name)}</b> $emp لديها بوظيفة <b>{$h($pos)}</b>"
              . ($e['start_date'] ? " منذ تاريخ <b>{$date($e['start_date'])}</b>" : '') . ($e['status'] === 'inactive' && $e['termination_date'] ? " حتى تاريخ <b>{$date($e['termination_date'])}</b>" : '')
              . ' وما زال على رأس العمل حتى تاريخه.' ;
        if ($e['status'] === 'inactive') $body = str_replace(' وما زال على رأس العمل حتى تاريخه.', '.', $body);
        $body .= '<br><br>وقد أُعطيت له هذه الشهادة بناءً على طلبه دون أدنى مسؤولية على الشركة تجاه الغير.';
    } elseif ($type === 'salary') {
        $sal = (float)$e['salary'];
        $body = "تشهد شركة <b>{$h($co['name'])}</b> بأن السيد/السيدة <b>{$h($name)}</b> $emp لديها بوظيفة <b>{$h($pos)}</b>"
              . ($e['start_date'] ? " منذ تاريخ <b>{$date($e['start_date'])}</b>" : '') . ' ويتقاضى راتباً شهرياً إجمالياً قدره '
              . "<b>{$num(number_format($sal, 2))} $curName</b> (<b>{$h(arabic_money_words($sal, $cur))}</b>).<br><br>وقد أُعطيت له هذه الشهادة بناءً على طلبه دون أدنى مسؤولية على الشركة تجاه الغير.";
    } else {
        $end = $e['termination_date'] ?: $today;
        $years = $e['start_date'] ? law_years_between($e['start_date'], $end) : 0;
        $dur = $years >= 1 ? $num((int)floor($years)) . ' سنة' . (round(($years - floor($years)) * 12) >= 1 ? ' و' . $num((int)round(($years - floor($years)) * 12)) . ' شهراً' : '') : $num(max(1, (int)round($years * 12))) . ' شهراً';
        $body = "تشهد شركة <b>{$h($co['name'])}</b> بأن السيد/السيدة <b>{$h($name)}</b> عمل لديها بوظيفة <b>{$h($pos)}</b>"
              . ($e['start_date'] ? " اعتباراً من <b>{$date($e['start_date'])}</b>" : '') . ($e['termination_date'] ? " حتى <b>{$date($e['termination_date'])}</b>" : ' وما زال يعمل حتى تاريخه')
              . " لمدة <b>$dur</b>، وكان خلالها مجتهداً وملتزماً بالعمل.<br><br>ونتمنى له دوام التوفيق والنجاح.";
    }
    return '<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>' . $h($title) . ' - ' . $h($name) . '</title>'
        . '<style>@page{size:A4;margin:22mm 20mm}body{font-family:"Segoe UI",Tahoma,"Noto Naskh Arabic",Arial,sans-serif;color:#111;line-height:2.1;font-size:19px;margin:0;background:#f2f2f2}'
        . '.page{max-width:780px;margin:24px auto;background:#fff;padding:56px 64px;box-shadow:0 2px 14px rgba(0,0,0,.12)}h1{text-align:center;font-size:30px;margin:18px 0 34px;border-bottom:2px solid #111;display:inline-block;padding:0 24px 6px}'
        . '.top{display:flex;justify-content:space-between;align-items:flex-start;gap:12px}.co{font-size:24px;font-weight:700}.meta{font-size:15px;color:#444;text-align:left}.center{text-align:center}'
        . '.sign{margin-top:70px;display:flex;justify-content:space-between;font-size:17px}.btn{position:fixed;top:12px;left:12px;background:#0b6e6e;color:#fff;border:0;border-radius:6px;padding:10px 18px;font-size:16px;cursor:pointer}'
        . '@media print{body{background:#fff}.page{box-shadow:none;margin:0;padding:0}.btn{display:none}}</style></head><body>'
        . '<button class="btn" onclick="window.print()">طباعة / حفظ PDF</button><div class="page"><div class="top"><div class="co">' . $h($co['name']) . '</div>'
        . '<div class="meta">التاريخ: ' . $h($date($today)) . '<br>الرقم المرجعي: ' . $h($num(strtoupper(substr($type, 0, 1)) . '-' . $e['id'] . '-' . gmdate('Ymd'))) . '</div></div>'
        . '<div class="center"><h1>' . $h($title) . '</h1></div><p>السادة / ' . ($type === 'salary' ? 'من يهمه الأمر' : 'من يهمه الأمر') . '<br>تحية طيبة وبعد،</p><p>' . $body . '</p>'
        . '<div class="sign"><div>مدير الموارد البشرية<br><br>......................</div><div>الختم<br><br>......................</div></div></div></body></html>';
}

// ------------------------------------------------------------------ voice

/** Normalise Arabic for matching: no diacritics or tatweel, one form of alef / ya / ta marbuta / hamza. */
function arabic_normalize(string $t): string {
    $t = preg_replace('/[\x{064B}-\x{065F}\x{0670}\x{0640}]/u', '', $t);
    $t = strtr($t, ['أ' => 'ا', 'إ' => 'ا', 'آ' => 'ا', 'ى' => 'ي', 'ة' => 'ه', 'ؤ' => 'و', 'ئ' => 'ي', '٠' => '0', '١' => '1', '٢' => '2', '٣' => '3', '٤' => '4', '٥' => '5', '٦' => '6', '٧' => '7', '٨' => '8', '٩' => '9']);
    return trim(preg_replace('/\s+/u', ' ', mb_strtolower($t)));
}

/** Which command is this? Returns [intent, target|null]. Order matters: actions first, then screens, then questions. */
function arabic_voice_intent(string $q): array {
    $n = arabic_normalize($q);
    $has = fn(string $re) => (bool)preg_match($re . 'u', $n);
    if ($has('/^هل .*(سجلت|حضرت|بصمت|وصلت)/')) return ['attendance', null];           // a question, not a command
    if ($has('/(سجل|سجلني|بصم|بصمني|حضرني|ابدا).*(حضور|دخول|وصلت|شغل)|وصلت الشغل|انا وصلت|بصمه دخول/')) return ['check_in', null];
    if ($has('/(سجل|سجلني|بصم|بصمني).*(انصراف|خروج|مشي)|خلصت شغل|ماشي دلوقتي|بصمه خروج|انصراف/')) return ['check_out', null];
    if ($has('/(افتح|روح|وديني|اعرض|فتح|ورني|ورنيي)/')) {
        $screens = [
            'meetings' => '/(اجتماع|اجتماعات|ميتنج|مكالمه)/', 'payslips' => '/(قسيمه|مرتب|راتب|كشف)/', 'attendance' => '/(حضور|انصراف|بصمه|دوام)/',
            'requests' => '/(طلب|طلبات|اجازه|اجازات)/', 'rewards' => '/(نقاط|مكافا|جوايز)/', 'announcements' => '/(اعلان|اعلانات|اخبار)/',
            'holidays' => '/(عطل|عطله|اجازات رسميه)/', 'team' => '/(فريق|زملاء)/', 'approvals' => '/(موافق|اعتماد)/', 'documents' => '/(مستند|اوراق|ملفات)/',
            'people' => '/(موظف|موظفين|الناس)/', 'payroll' => '/(مرتبات|رواتب)/', 'career' => '/(مسار|ترقي|ترقيه)/', 'decisions' => '/(قرار|قرارات|اعتراض)/',
            'field' => '/(زيار|ميدان)/', 'coach' => '/(نصاي|مدرب)/', 'inbox' => '/(اشعار|تنبيه|رسائل)/',
        ];
        foreach ($screens as $target => $re) if ($has($re)) return ['navigate', $target];
        return ['navigate', 'home'];
    }
    if ($has('/(عايز|عاوز|اريد|ابغي|ابي|محتاج|اطلب).*(اجازه|اجازة)/')) return ['request_leave', 'requests'];
    if ($has('/(كام|كم|ايه|ما هو|ما هي|اي).*(رصيد|باقي|متبقي).*(اجاز)|رصيد.*اجاز|رصيدي/')) return ['leave_balance', null];
    if ($has('/(نقاط|نقطتي|مستواي|مستوي)/')) return ['points', null];
    if ($has('/(مرتب|راتب|قسيمه)/')) return ['payslip', null];
    if ($has('/(الاجازه الرسميه|العطله|عطله|اجازه رسميه|اجازه قادمه)/')) return ['holiday', null];
    if ($has('/(سجلت|حضرت|بصمت)/')) return ['attendance', null];
    if ($has('/(متاخر|اتاخرت|تاخير)/')) return ['late', null];
    if ($has('/(وردي|دوام|مواعيد|ساعات)/')) return ['shift', null];
    if ($has('/(مديري|مدير)/')) return ['manager', null];
    if ($has('/(عدد|كام).*(موظف)/')) return ['hr_headcount', null];
    if ($has('/(مين|من).*(غايب|غياب)/')) return ['hr_absent', null];
    if ($has('/(مين|من).*(اجازه)/')) return ['hr_on_leave', null];
    if ($has('/(معلق|ينتظر|موافقات)/')) return ['hr_pending', null];
    if ($has('/(مساعده|اعمل ايه|تعمل ايه|ايه اللي)/')) return ['help', null];
    return ['unknown', null];
}

function arabic_voice(PDO $pdo, array $b): void {
    $text = trim((string)($b['text'] ?? ''));
    if ($text === '' || mb_strlen($text) > 300) error_response('Say a short sentence', 422);
    [$intent, $target] = arabic_voice_intent($text);
    $out = ['heard' => $text, 'intent' => $intent, 'target' => $target, 'confirm' => false, 'answer' => null, 'actions' => []];
    if ($intent === 'check_in' || $intent === 'check_out') {
        if (own_employee_id() <= 0) { $out['answer'] = 'هذا الحساب غير مرتبط بسجل موظف.'; $out['intent'] = 'unknown'; }
        else {
            $out['confirm'] = true;
            $out['answer'] = $intent === 'check_in' ? 'هل تريد تسجيل حضورك الآن؟ سأحتاج موقعك الحالي.' : 'هل تريد تسجيل انصرافك الآن؟ سأحتاج موقعك الحالي.';
        }
    } elseif ($intent === 'navigate') {
        $out['answer'] = 'حاضر، سأفتح الشاشة المطلوبة.';
    } elseif ($intent === 'request_leave') {
        $out['answer'] = 'سأفتح لك الطلبات لتقدّم إجازة.';
    } elseif ($intent === 'unknown') {
        $out['answer'] = 'لم أفهم الطلب. جرّب مثلاً: «سجل حضوري» أو «كم رصيد إجازاتي» أو «افتح قسيمة المرتب».';
    } else {
        require_once __DIR__ . '/assistant.php';
        if (str_starts_with($intent, 'hr_') && !is_hr()) { $out['answer'] = 'هذه المعلومة متاحة للموارد البشرية فقط.'; }
        elseif (!str_starts_with($intent, 'hr_') && $intent !== 'help' && own_employee_id() <= 0) { $out['answer'] = 'هذا الحساب غير مرتبط بسجل موظف.'; }
        else { $r = assistant_answer($pdo, $intent, true); $out['answer'] = $r['answer']; $out['actions'] = $r['actions'] ?? []; }
    }
    $out['say'] = $out['answer'];
    json_response(['success' => true, 'data' => $out]);
}
