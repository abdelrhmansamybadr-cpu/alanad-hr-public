<?php
/**
 * Local labour law (feature `local_laws`).
 *
 *   GET /labor-law/packs                       the country packs (for the settings screen)            (HR)
 *   GET /labor-law/summary                     my company's pack + what it means for ME                (everyone)
 *   PUT /labor-law/settings                    {country: EG|SA|null, params: {...}}                    (company admin)
 *   GET /labor-law/eos?employee_id=&reason=    end-of-service estimate (Saudi pack)                    (HR, or the employee's own)
 *   GET /labor-law/hijri?date=YYYY-MM-DD       Hijri date                                              (everyone)
 */
require_once __DIR__ . '/../helpers/labor_law.php';
require_once __DIR__ . '/../helpers/payroll_extra.php';      // payroll_progressive_tax()

function handle_labor_law(string $path, string $method, array $body): void {
    $pdo = getDB();
    $sub = explode('/', $path)[1] ?? '';
    switch ($sub) {
        case 'packs':    if ($method !== 'GET') error_response('Method not allowed', 405); require_hr(); law_api_packs(); break;
        case 'summary':  if ($method !== 'GET') error_response('Method not allowed', 405); law_api_summary($pdo); break;
        case 'settings': if ($method !== 'PUT') error_response('Method not allowed', 405); require_admin(); law_api_settings($pdo, $body); break;
        case 'eos':      if ($method !== 'GET') error_response('Method not allowed', 405); law_api_eos($pdo); break;
        case 'hijri':    if ($method !== 'GET') error_response('Method not allowed', 405); law_api_hijri(); break;
        default:         error_response('Endpoint not found: labor-law/' . $sub, 404);
    }
}

function law_api_packs(): void {
    $out = [];
    foreach (law_packs() as $code => $p) $out[] = ['code' => $code] + $p;
    json_response(['success' => true, 'data' => $out]);
}

function law_api_hijri(): void {
    $d = (string)($_GET['date'] ?? gmdate('Y-m-d'));
    if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $d) || !strtotime($d)) error_response('date must be YYYY-MM-DD', 422);
    json_response(['success' => true, 'data' => law_hijri($d)]);
}

function law_api_settings(PDO $pdo, array $body): void {
    $country = $body['country'] ?? null;
    if ($country !== null && $country !== '') {
        $country = strtoupper((string)$country);
        if (!isset(law_packs()[$country])) error_response('Unknown country', 422);
    } else {
        $country = null;
    }
    $clean = [];
    if (isset($body['params']) && is_array($body['params'])) {
        $clean = law_clean_params($body['params']);
        if (is_string($clean)) error_response($clean, 422);
    }
    $pdo->prepare("UPDATE companies SET law_country = ?, law_params = ? WHERE id = ?")
        ->execute([$country, $clean ? json_encode($clean) : null, cid()]);
    audit($pdo, 'update', 'labor_law', cid(), ['country' => $country, 'params' => $clean]);
    law_api_summary($pdo);
}

function law_api_summary(PDO $pdo): void {
    $law = law_company($pdo);
    $today = gmdate('Y-m-d');
    $out = ['configured' => $law !== null, 'country' => $law['country'] ?? null, 'hijri_today' => law_hijri($today), 'gregorian_today' => $today];
    if ($law) {
        $out['pack'] = ['name_en' => $law['pack']['name_en'], 'name_ar' => $law['pack']['name_ar'], 'currency' => $law['pack']['currency'],
                        'reviewed' => $law['pack']['reviewed'], 'rules' => $law['pack']['rules'],
                        'notes_en' => $law['pack']['notes_en'], 'notes_ar' => $law['pack']['notes_ar']];
        $out['params'] = $law['params'];
        $out['edited'] = array_map(fn($k) => lcfirst(str_replace(' ', '', ucwords(str_replace('_', ' ', $k)))), array_keys($law['overrides']));
        $eid = own_employee_id();
        if ($eid > 0) {
            $s = $pdo->prepare("SELECT start_date, birth_date, salary FROM employees WHERE id = ? AND company_id = ?");
            $s->execute([$eid, cid()]);
            if ($e = $s->fetch()) {
                $p = $law['params'];
                $salary = (float)$e['salary'];
                $insurable = $p['insurance_cap'] > 0 ? min($salary, (float)$p['insurance_cap']) : $salary;
                $ins = round($insurable * (float)$p['insurance_pct'] / 100, 2);
                $taxable = max(0.0, $salary - $ins - (float)$p['tax_monthly_exemption']);
                $tax = $p['tax_brackets'] ? payroll_progressive_tax((array)$p['tax_brackets'], $taxable) : 0.0;
                $probEnd = $e['start_date'] ? (new DateTime($e['start_date']))->modify('+' . (int)$law['pack']['rules']['probation_months'] . ' months')->format('Y-m-d') : null;
                $out['me'] = [
                    'annual_leave_days' => law_annual_leave_days($law, $e['start_date'], $e['birth_date'], $today),
                    'years_of_service' => $e['start_date'] ? round(law_years_between($e['start_date'], $today), 2) : 0,
                    'probation_ends' => $probEnd, 'probation_over' => $probEnd !== null && $probEnd <= $today,
                    'monthly_insurance' => $ins, 'monthly_tax' => $tax, 'salary' => $salary, 'net_estimate' => round($salary - $ins - $tax, 2),
                    'start_date_hijri' => $e['start_date'] ? law_hijri($e['start_date']) : null,
                ];
            }
        }
    }
    json_response(['success' => true, 'data' => $out]);
}

function law_api_eos(PDO $pdo): void {
    $law = law_company($pdo);
    if (!$law) error_response('No labour law pack is active for this company.', 409);
    $eid = is_hr() ? (int)($_GET['employee_id'] ?? 0) : own_employee_id();
    if ($eid <= 0) error_response('employee_id is required', 422);
    if (!is_hr() && $eid !== own_employee_id()) error_response('Forbidden. Insufficient permissions.', 403);
    if (!employee_in_company($pdo, $eid)) error_response('Employee not found', 404);
    if (($law['pack']['rules']['eos'] ?? 'none') !== 'sa') {
        json_response(['success' => true, 'data' => ['applicable' => false, 'note_en' => 'This country has no statutory end-of-service payment.', 'note_ar' => 'لا توجد مكافأة نهاية خدمة نظامية في هذا البلد.']]);
    }
    $s = $pdo->prepare("SELECT start_date, salary, termination_date FROM employees WHERE id = ? AND company_id = ?");
    $s->execute([$eid, cid()]);
    $e = $s->fetch();
    if (!$e['start_date']) error_response('The employee has no start date', 422);
    $reason = ($_GET['reason'] ?? 'termination') === 'resignation' ? 'resignation' : 'termination';
    $end = !empty($_GET['end_date']) && preg_match('/^\d{4}-\d{2}-\d{2}$/', (string)$_GET['end_date']) ? (string)$_GET['end_date'] : ($e['termination_date'] ?: gmdate('Y-m-d'));
    $r = law_eos_sa((float)$e['salary'], law_years_between($e['start_date'], $end), $reason);
    $r['applicable'] = true; $r['end_date'] = $end;
    $r['note_en'] = 'Estimate on the full monthly wage recorded for the employee. The legal wage for this award is the last wage including allowances.';
    $r['note_ar'] = 'تقدير على أساس الأجر الشهري المسجل للموظف. الأجر النظامي لهذه المكافأة هو آخر أجر شامل البدلات.';
    json_response(['success' => true, 'data' => $r]);
}
