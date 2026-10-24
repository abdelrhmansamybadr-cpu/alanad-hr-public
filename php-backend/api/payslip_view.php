<?php
/**
 * GET /payslip-view?t=<signed token>&lang=en|ar
 *
 * A printable payslip page (use the browser's Print -> Save as PDF). No login header is needed because
 * the link itself is signed and expires after 10 minutes; it is handed out by GET /payroll/{id}/link.
 */
require_once __DIR__ . '/../helpers/payroll_extra.php';

function handle_payslip_view(): void {
    $pdo = getDB();
    $chk = payslip_token_check($pdo, (string)($_GET['t'] ?? ''));
    header('Content-Type: text/html; charset=utf-8');
    header('Cache-Control: no-store');
    header('X-Robots-Tag: noindex');
    if (!$chk) {
        http_response_code(403);
        echo '<!doctype html><meta charset="utf-8"><body style="font-family:sans-serif;text-align:center;padding:60px"><h2>This link has expired</h2><p>Open the payslip again from the app or the website.</p></body>';
        exit;
    }
    [$payrollId, $companyId] = $chk;
    $ar = ($_GET['lang'] ?? 'en') === 'ar';

    $s = $pdo->prepare(
        "SELECT p.*, CONCAT(e.first_name, ' ', e.last_name) AS employee_name, e.position, d.name AS department_name
         FROM payroll p JOIN employees e ON e.id = p.employee_id LEFT JOIN departments d ON d.id = e.department_id
         WHERE p.id = ? AND p.company_id = ?"
    );
    $s->execute([$payrollId, $companyId]);
    $p = $s->fetch();
    $c = $pdo->prepare("SELECT name, currency, primary_color FROM companies WHERE id = ?");
    $c->execute([$companyId]);
    $co = $c->fetch();
    if (!$p || !$co) { http_response_code(404); echo 'Not found'; exit; }

    $t = fn(string $en, string $arText) => $ar ? $arText : $en;
    $h = fn($v) => htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8');
    $num = fn($v) => number_format((float)$v, 2, '.', ',');
    $cur = $h($co['currency'] ?? '');
    $color = preg_match('/^#[0-9a-fA-F]{6}$/', (string)($co['primary_color'] ?? '')) ? $co['primary_color'] : '#00617A';

    $labels = [
        'absent' => 'أيام الغياب', 'unpaid_leave' => 'أيام إجازة بدون أجر', 'half_day' => 'أنصاف الأيام', 'late' => 'دقائق التأخير',
        'overtime' => 'الوقت الإضافي (ساعات)', 'perfect' => 'مكافأة الحضور المثالي', 'insurance' => 'التأمينات الاجتماعية', 'tax' => 'ضريبة الدخل',
    ];
    $earn = [[$t('Base salary', 'الراتب الأساسي'), (float)$p['base_salary']]];
    $ded = [];
    $bd = json_decode((string)($p['breakdown'] ?? ''), true);
    if (!empty($bd['lines'])) {
        foreach ($bd['lines'] as $l) {
            $key = (string)($l['key'] ?? '');
            $label = $ar ? ($labels[$key] ?? (str_starts_with($key, 'loan_') ? 'قسط سلفة: ' . preg_replace('/^Loan: /', '', (string)$l['label']) : (string)$l['label'])) : (string)$l['label'];
            if ((float)$l['amount'] >= 0) $earn[] = [$label, (float)$l['amount']];
            else $ded[] = [$label, abs((float)$l['amount'])];
        }
    } else {
        if ((float)$p['bonus'] != 0) $earn[] = [$t('Bonus', 'مكافأة'), (float)$p['bonus']];
        if ((float)$p['deductions'] != 0) $ded[] = [$t('Deductions', 'خصومات'), (float)$p['deductions']];
    }
    $gross = array_sum(array_column($earn, 1));
    $dedTotal = array_sum(array_column($ded, 1));
    $monthNames = $ar ? ['', 'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر']
                      : ['', 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    $period = ($monthNames[(int)$p['month']] ?? $p['month']) . ' ' . $p['year'];
    $status = ['paid' => $t('Paid', 'مدفوعة'), 'pending' => $t('Pending', 'قيد الدفع'), 'cancelled' => $t('Cancelled', 'ملغاة')][$p['status']] ?? $p['status'];

    $rows = function (array $list) use ($h, $num, $cur) {
        $out = '';
        foreach ($list as [$label, $amt]) $out .= '<tr><td>' . $h($label) . '</td><td class="n">' . $num($amt) . ' ' . $cur . '</td></tr>';
        return $out ?: '<tr><td colspan="2" class="mute">—</td></tr>';
    };

    echo '<!doctype html><html lang="' . ($ar ? 'ar' : 'en') . '" dir="' . ($ar ? 'rtl' : 'ltr') . '"><head><meta charset="utf-8">'
        . '<meta name="viewport" content="width=device-width,initial-scale=1"><title>' . $h($t('Payslip', 'قسيمة الراتب')) . ' - ' . $h($p['employee_name']) . ' - ' . $h($period) . '</title><style>'
        . '*{box-sizing:border-box}body{margin:0;background:#F3F4F6;font-family:Segoe UI,Tahoma,Arial,sans-serif;color:#111827}'
        . '.page{max-width:760px;margin:24px auto;background:#fff;border-radius:16px;padding:32px;box-shadow:0 4px 24px rgba(0,0,0,.08)}'
        . '.top{display:flex;justify-content:space-between;align-items:flex-start;border-bottom:3px solid ' . $color . ';padding-bottom:16px;margin-bottom:18px}'
        . 'h1{margin:0;font-size:22px}h2{font-size:14px;color:#6B7280;margin:0 0 6px;font-weight:600;text-transform:uppercase;letter-spacing:.04em}'
        . '.meta{display:grid;grid-template-columns:1fr 1fr;gap:10px 24px;margin-bottom:22px;font-size:14px}.meta b{display:block;color:#6B7280;font-weight:600;font-size:12px}'
        . 'table{width:100%;border-collapse:collapse;margin-bottom:18px;font-size:14px}td{padding:9px 6px;border-bottom:1px solid #E5E7EB}.n{text-align:' . ($ar ? 'left' : 'right') . ';white-space:nowrap;font-variant-numeric:tabular-nums}'
        . '.tot td{font-weight:700;border-bottom:2px solid #D1D5DB}.net{display:flex;justify-content:space-between;align-items:center;background:' . $color . ';color:#fff;border-radius:12px;padding:16px 18px;font-size:18px;font-weight:800}'
        . '.mute{color:#9CA3AF}.foot{margin-top:20px;font-size:12px;color:#9CA3AF;text-align:center}.btn{display:block;margin:18px auto 0;padding:11px 22px;border:0;border-radius:10px;background:' . $color . ';color:#fff;font-size:15px;font-weight:700;cursor:pointer}'
        . '@media print{body{background:#fff}.page{box-shadow:none;margin:0;border-radius:0;max-width:none}.btn{display:none}}'
        . '</style></head><body><div class="page">'
        . '<div class="top"><div><h1>' . $h($co['name']) . '</h1><div class="mute">' . $h($t('Payslip', 'قسيمة الراتب')) . ' · ' . $h($period) . '</div></div><div class="mute">' . $h($status) . '</div></div>'
        . '<div class="meta"><div><b>' . $h($t('Employee', 'الموظف')) . '</b>' . $h($p['employee_name']) . '</div><div><b>' . $h($t('Position', 'المسمى الوظيفي')) . '</b>' . $h($p['position'] ?: '—') . '</div>'
        . '<div><b>' . $h($t('Department', 'القسم')) . '</b>' . $h($p['department_name'] ?: '—') . '</div><div><b>' . $h($t('Period', 'الفترة')) . '</b>' . $h($period) . '</div></div>'
        . '<h2>' . $h($t('Earnings', 'المستحقات')) . '</h2><table>' . $rows($earn) . '<tr class="tot"><td>' . $h($t('Total earnings', 'إجمالي المستحقات')) . '</td><td class="n">' . $num($gross) . ' ' . $cur . '</td></tr></table>'
        . '<h2>' . $h($t('Deductions', 'الخصومات')) . '</h2><table>' . $rows($ded) . '<tr class="tot"><td>' . $h($t('Total deductions', 'إجمالي الخصومات')) . '</td><td class="n">' . $num($dedTotal) . ' ' . $cur . '</td></tr></table>'
        . '<div class="net"><span>' . $h($t('Net pay', 'صافي الراتب')) . '</span><span>' . $num($p['net_pay']) . ' ' . $cur . '</span></div>'
        . '<button class="btn" onclick="window.print()">' . $h($t('Print / Save as PDF', 'طباعة / حفظ PDF')) . '</button>'
        . '<div class="foot">' . $h($t('Generated by Al Anad HR', 'صدرت من Al Anad HR')) . ' · ' . gmdate('Y-m-d H:i') . ' UTC</div>'
        . '</div></body></html>';
    exit;
}
