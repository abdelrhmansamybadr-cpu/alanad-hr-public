<?php
/**
 * Local labour law packs (feature `local_laws`): Egypt and Saudi Arabia.
 *
 * A pack holds the default rules of a country: social insurance share, income-tax brackets, annual leave by length of
 * service, probation, working hours, overtime, notice and (Saudi) end-of-service. The money figures are YEARLY-CHANGING
 * numbers, so every company can edit them (companies.law_params overrides the pack) and the pack says which year it
 * was last checked. With the feature on and a country chosen, payroll_policy() follows the pack automatically; with it
 * off, payroll goes back to the company's own manual settings.
 */

function law_packs(): array {
    return [
        'EG' => [
            'name_en' => 'Egypt', 'name_ar' => 'مصر', 'currency' => 'EGP', 'reviewed' => '2025',
            'params' => [
                'insurance_pct' => 11.0,                // employee share of the insurable wage
                'insurance_cap' => 16700.0,             // maximum insurable monthly wage (revised every January)
                'tax_monthly_exemption' => 1666.67,     // personal exemption 20,000 a year
                'tax_brackets' => ['3333.33|0', '4583.33|10', '5833.33|15', '16666.67|20', '33333.33|22.5', '100000|25', '|27.5'],
                'overtime_multiplier' => 1.35,          // daytime overtime: at least 135% of the normal hourly pay
            ],
            'rules' => [
                'annual_leave_days' => 21, 'annual_leave_days_long' => 30, 'long_after_years' => 10, 'long_after_age' => 50,
                'probation_months' => 3, 'daily_hours' => 8, 'weekly_hours' => 48, 'notice_days' => 60,
                'weekly_rest' => 'Friday', 'eos' => 'none',
            ],
            'notes_en' => 'Employee insurance share and tax brackets follow the 2025 figures. Confirm the yearly insurance ceiling with your accountant and edit it here when it changes. Egypt has no statutory end-of-service payment: the pension comes from social insurance.',
            'notes_ar' => 'نسبة التأمين وشرائح الضرائب حسب أرقام 2025. راجع حد الأجر التأميني كل سنة مع المحاسب وعدّله هنا عند تغييره. لا توجد مكافأة نهاية خدمة نظامية في مصر، والمعاش يأتي من التأمينات الاجتماعية.',
        ],
        'SA' => [
            'name_en' => 'Saudi Arabia', 'name_ar' => 'السعودية', 'currency' => 'SAR', 'reviewed' => '2025',
            'params' => [
                'insurance_pct' => 10.5,                // GOSI, Saudi nationals: 9.75% annuities + 0.75% SANED
                'insurance_cap' => 45000.0,             // maximum contributory wage (basic + housing)
                'tax_monthly_exemption' => 0.0,
                'tax_brackets' => [],                   // no income tax on employees
                'overtime_multiplier' => 1.5,           // 150% of the basic hourly wage
            ],
            'rules' => [
                'annual_leave_days' => 21, 'annual_leave_days_long' => 30, 'long_after_years' => 5, 'long_after_age' => 0,
                'probation_months' => 3, 'daily_hours' => 8, 'weekly_hours' => 48, 'notice_days' => 60,
                'weekly_rest' => 'Friday', 'eos' => 'sa',
            ],
            'notes_en' => 'The GOSI share applies to Saudi nationals; for foreign employees the employee share is 0, so lower the percentage if most of your staff are not Saudi. Probation can be extended up to 180 days by agreement.',
            'notes_ar' => 'نسبة التأمينات (GOSI) تخص المواطنين السعوديين، وللموظف الأجنبي تكون صفراً، فقلّل النسبة إذا كان أغلب موظفيك غير سعوديين. يمكن تمديد التجربة حتى 180 يوماً بالاتفاق.',
        ],
    ];
}

/** Keys of the pack that a company may override, with their kind. */
function law_param_kinds(): array {
    return ['insurance_pct' => 'pct', 'insurance_cap' => 'money', 'tax_monthly_exemption' => 'money', 'tax_brackets' => 'list', 'overtime_multiplier' => 'mult'];
}

/** The company's law setup: ['country', 'pack', 'params' (pack merged with the company's edits), 'overrides'] or null. */
function law_company(PDO $pdo, ?int $companyId = null): ?array {
    $companyId = $companyId ?? cid();
    if (!feature_enabled($pdo, 'local_laws', $companyId)) return null;
    $c = company_get($pdo, $companyId);
    $cc = strtoupper((string)($c['law_country'] ?? ''));
    $packs = law_packs();
    if (!isset($packs[$cc])) return null;
    $over = json_decode((string)($c['law_params'] ?? ''), true);
    $over = is_array($over) ? array_intersect_key($over, law_param_kinds()) : [];
    return ['country' => $cc, 'pack' => $packs[$cc], 'params' => array_merge($packs[$cc]['params'], $over), 'overrides' => $over];
}

/** payroll_policy() hook: with a law pack active, insurance, tax and overtime follow it. */
function law_overlay_payroll_policy(PDO $pdo, array $pol): array {
    try {
        if (!function_exists('cid') || empty($GLOBALS['HR_USER'])) return $pol;
        $law = law_company($pdo);
    } catch (Throwable $e) { return $pol; }
    if (!$law) return $pol;
    $p = $law['params'];
    $pol['insurance_pct'] = (float)$p['insurance_pct'];
    $pol['insurance_cap'] = (float)$p['insurance_cap'];
    $pol['tax_monthly_exemption'] = (float)$p['tax_monthly_exemption'];
    $pol['tax_brackets'] = array_values($p['tax_brackets']);
    $pol['tax_mode'] = $p['tax_brackets'] ? 'brackets' : 'none';
    $pol['tax_flat_pct'] = 0.0;
    $pol['overtime_multiplier'] = (float)$p['overtime_multiplier'];
    $pol['_law_country'] = $law['country'];
    return $pol;
}

/** Validate edits coming from the admin; returns the clean overrides or an error string. */
function law_clean_params(array $in) {
    $out = [];
    foreach (law_param_kinds() as $k => $kind) {
        if (!array_key_exists($k, $in)) continue;
        $v = $in[$k];
        if ($kind === 'list') {
            $list = [];
            foreach ((array)$v as $step) {
                $step = trim((string)$step);
                if ($step === '') continue;
                if (!preg_match('/^(\d+(\.\d+)?)?\|\d+(\.\d+)?$/', $step)) return "Invalid tax step: $step (use upTo|rate, e.g. 5000|10)";
                $list[] = $step;
            }
            $out[$k] = $list;
        } else {
            if (!is_numeric($v) || (float)$v < 0) return "$k must be a number, zero or more";
            $max = ['pct' => 100, 'mult' => 5, 'money' => 100000000][$kind];
            if ((float)$v > $max) return "$k is too large";
            $out[$k] = round((float)$v, 2);
        }
    }
    return $out;
}

// ------------------------------------------------------------------ service, leave, end of service

function law_years_between(string $from, string $to): float {
    $a = new DateTime($from); $b = new DateTime($to);
    if ($b < $a) return 0.0;
    $d = $a->diff($b);
    return $d->y + $d->m / 12 + $d->d / 365;
}

function law_annual_leave_days(array $law, ?string $startDate, ?string $birthDate, string $on): int {
    $r = $law['pack']['rules'];
    $years = $startDate ? law_years_between($startDate, $on) : 0;
    $age = $birthDate ? law_years_between($birthDate, $on) : 0;
    if ($years >= $r['long_after_years'] || ($r['long_after_age'] > 0 && $age >= $r['long_after_age'])) return (int)$r['annual_leave_days_long'];
    return (int)$r['annual_leave_days'];
}

/** Saudi end-of-service award. $reason: 'termination' (employer ended it, or contract ended) | 'resignation'. */
function law_eos_sa(float $monthlyWage, float $years, string $reason): array {
    $first = min($years, 5.0);
    $rest = max(0.0, $years - 5.0);
    $full = $monthlyWage * 0.5 * $first + $monthlyWage * 1.0 * $rest;
    $share = 1.0;
    if ($reason === 'resignation') {
        $share = $years < 2 ? 0.0 : ($years < 5 ? 1 / 3 : ($years < 10 ? 2 / 3 : 1.0));
    }
    return [
        'years' => round($years, 2), 'monthly_wage' => round($monthlyWage, 2), 'reason' => $reason,
        'full_award' => round($full, 2), 'share' => round($share, 4), 'amount' => round($full * $share, 2),
        'breakdown' => ['half_month_per_year_first_5' => round($monthlyWage * 0.5 * $first, 2), 'full_month_per_year_after_5' => round($monthlyWage * $rest, 2)],
    ];
}

// ------------------------------------------------------------------ Hijri calendar

const LAW_HIJRI_MONTHS_AR = ['محرم', 'صفر', 'ربيع الأول', 'ربيع الآخر', 'جمادى الأولى', 'جمادى الآخرة', 'رجب', 'شعبان', 'رمضان', 'شوال', 'ذو القعدة', 'ذو الحجة'];
const LAW_HIJRI_MONTHS_EN = ['Muharram', 'Safar', "Rabi' al-awwal", "Rabi' al-thani", 'Jumada al-awwal', 'Jumada al-thani', 'Rajab', "Sha'ban", 'Ramadan', 'Shawwal', "Dhu al-Qi'dah", 'Dhu al-Hijjah'];

/** Gregorian date (Y-m-d) -> Hijri. Uses the Umm al-Qura calendar when PHP intl is available, else the tabular calendar (can differ by a day). */
function law_hijri(string $ymd): array {
    $dt = new DateTime($ymd . ' 12:00:00', new DateTimeZone('UTC'));
    $y = $m = $d = 0; $source = 'tabular';
    if (class_exists('IntlDateFormatter')) {
        $f = new IntlDateFormatter('en_US@calendar=islamic-umalqura', IntlDateFormatter::NONE, IntlDateFormatter::NONE, 'UTC', IntlDateFormatter::TRADITIONAL, 'y-M-d');
        $s = $f ? $f->format($dt) : false;
        if ($s && preg_match('/^(\d+)-(\d+)-(\d+)$/', $s, $mm)) { [$y, $m, $d] = [(int)$mm[1], (int)$mm[2], (int)$mm[3]]; $source = 'umalqura'; }
    }
    if (!$y) {
        // tabular Islamic calendar (civil epoch), from the Julian day number
        $jd = (int)floor($dt->getTimestamp() / 86400 + 2440587.5 + 0.5);
        $l = $jd - 1948440 + 10632;
        $n = intdiv($l - 1, 10631);
        $l = $l - 10631 * $n + 354;
        $j = intdiv(10985 - $l, 5316) * intdiv(50 * $l, 17719) + intdiv($l, 5670) * intdiv(43 * $l, 15238);
        $l = $l - intdiv(30 - $j, 15) * intdiv(17719 * $j, 50) - intdiv($j, 16) * intdiv(15238 * $j, 43) + 29;
        $m = intdiv(24 * $l, 709);
        $d = $l - intdiv(709 * $m, 24);
        $y = 30 * $n + $j - 30;
    }
    $m = max(1, min(12, $m));
    return ['year' => $y, 'month' => $m, 'day' => $d, 'month_name_ar' => LAW_HIJRI_MONTHS_AR[$m - 1], 'month_name_en' => LAW_HIJRI_MONTHS_EN[$m - 1],
            'text_ar' => $d . ' ' . LAW_HIJRI_MONTHS_AR[$m - 1] . ' ' . $y . ' هـ', 'text_en' => $d . ' ' . LAW_HIJRI_MONTHS_EN[$m - 1] . ' ' . $y . ' AH', 'source' => $source];
}
