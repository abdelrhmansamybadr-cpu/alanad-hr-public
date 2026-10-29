<?php
/**
 * Payroll API handler (company-scoped)
 *
 *   GET    /payroll                 list (HR: all, filters employee_id, month=YYYY-MM, year, status; employee: own payslips)
 *   GET    /payroll/{id}            one payslip
 *   POST   /payroll                 create one record (HR)
 *   POST   /payroll/generate        {month, recalculate?}  pending payslips for everybody, built from attendance + the payroll policy (HR)
 *   GET    /payroll/preview?employee_id=&month=YYYY-MM   what the payslip would contain (HR)
 *   PUT    /payroll/pay-all         mark every pending record of a month as paid (HR)
 *   PUT    /payroll/{id}            edit / mark paid (HR)
 *   DELETE /payroll/{id}            delete (HR)
 *   GET    /payroll/loans           loans / advances with what is repaid and left (HR: all; employee: own)
 *   POST   /payroll/loans           {employee_id, title, amount, installment, start_month?} (HR)   PUT /payroll/loans/{id} {status|installment|title} (HR)
 *   GET    /payroll/{id}/link?lang= signed 10-minute link to a printable payslip page
 *
 * The app and portal send months as "YYYY-MM" text; the table stores month/year ints.
 */
require_once __DIR__ . '/attendance.php';
require_once __DIR__ . '/../helpers/payroll_extra.php';

function handle_payroll(string $path, string $method, array $body): void {
    $pdo      = getDB();
    $segments = explode('/', $path);
    $sub      = $segments[1] ?? '';
    $id       = ($sub !== '' && is_numeric($sub)) ? intval($sub) : null;

    if ($sub === 'loans') {
        payroll_loans_handle($segments, $method, $body, $pdo);
        return;
    }
    if ($id !== null && ($segments[2] ?? '') === 'link') {
        if ($method !== 'GET') error_response('Method not allowed', 405);
        payroll_payslip_link($id, $pdo);
        return;
    }
    if ($sub === 'generate') {
        if ($method !== 'POST') error_response('Method not allowed', 405);
        require_hr();
        payroll_generate($body, $pdo);
        return;
    }
    if ($sub === 'preview') {
        if ($method !== 'GET') error_response('Method not allowed', 405);
        require_hr();
        payroll_preview($pdo);
        return;
    }
    if ($sub === 'pay-all') {
        if ($method !== 'PUT') error_response('Method not allowed', 405);
        require_hr();
        payroll_pay_all($body, $pdo);
        return;
    }

    if ($id !== null) {
        switch ($method) {
            case 'GET':    payroll_get_one($id, $pdo); break;
            case 'PUT':    require_hr(); payroll_update($id, $body, $pdo); break;
            case 'DELETE': require_hr(); payroll_delete($id, $pdo); break;
            default:       error_response('Method not allowed', 405);
        }
    } else {
        switch ($method) {
            case 'GET':  payroll_list($pdo); break;
            case 'POST': require_hr(); payroll_create($body, $pdo); break;
            default:     error_response('Method not allowed', 405);
        }
    }
}

/** Returns [month(int), year(int|null)] from "YYYY-MM" or a plain month number. */
function payroll_split_month($raw): array {
    $raw = trim((string)$raw);
    if (preg_match('/^(\d{4})-(\d{1,2})/', $raw, $m)) {
        return [intval($m[2]), intval($m[1])];
    }
    if ($raw !== '' && ctype_digit($raw)) {
        return [intval($raw), null];
    }
    return [intval(date('n')), null];
}

/** Output month as "YYYY-MM" text, as the app/portal expect. */
function payroll_format_row(array $row): array {
    if (isset($row['month']) && isset($row['year'])) {
        $row['month'] = sprintf('%04d-%02d', (int)$row['year'], (int)$row['month']);
    }
    if (array_key_exists('breakdown', $row)) {
        $row['breakdown'] = !empty($row['breakdown']) ? json_decode($row['breakdown'], true) : null;
    }
    return $row;
}

function payroll_select(): string {
    return "SELECT p.*,
                   CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
                   e.position, e.department_id, e.avatar AS employee_avatar,
                   d.name AS department_name
            FROM payroll p
            JOIN employees e ON e.id = p.employee_id
            LEFT JOIN departments d ON d.id = e.department_id";
}

function payroll_list(PDO $pdo): void {
    $where  = ['p.company_id = ?'];
    $params = [cid()];

    if (!is_hr()) {
        $where[]  = 'p.employee_id = ?';
        $params[] = own_employee_id();
    } elseif (!empty($_GET['employee_id'])) {
        $where[]  = 'p.employee_id = ?';
        $params[] = intval($_GET['employee_id']);
    }
    if (!empty($_GET['month'])) {
        [$fm, $fy] = payroll_split_month($_GET['month']);
        $where[]  = 'p.month = ?';
        $params[] = $fm;
        if ($fy !== null) {
            $where[]  = 'p.year = ?';
            $params[] = $fy;
        }
    }
    if (!empty($_GET['year']))   { $where[] = 'p.year = ?';   $params[] = intval($_GET['year']); }
    if (!empty($_GET['status'])) { $where[] = 'p.status = ?'; $params[] = $_GET['status']; }

    $stmt = $pdo->prepare(payroll_select() . " WHERE " . implode(' AND ', $where) . " ORDER BY p.year DESC, p.month DESC, e.first_name");
    $stmt->execute($params);
    json_response(['success' => true, 'data' => array_map('payroll_format_row', $stmt->fetchAll())]);
}

function payroll_fetch(int $id, PDO $pdo): ?array {
    $stmt = $pdo->prepare(payroll_select() . " WHERE p.id = ? AND p.company_id = ?");
    $stmt->execute([$id, cid()]);
    $r = $stmt->fetch();
    return $r ? payroll_format_row($r) : null;
}

function payroll_get_one(int $id, PDO $pdo): void {
    $record = payroll_fetch($id, $pdo);
    if (!$record) {
        error_response('Payroll record not found', 404);
    }
    if (!is_hr() && (int)$record['employee_id'] !== own_employee_id()) {
        error_response('Forbidden. Insufficient permissions.', 403);
    }
    json_response(['success' => true, 'data' => $record]);
}

function payroll_create(array $body, PDO $pdo): void {
    $employeeId = intval($body['employee_id'] ?? 0);
    [$month, $yearFromMonth] = payroll_split_month($body['month'] ?? date('Y-m'));
    $year       = $yearFromMonth ?? intval($body['year'] ?? date('Y'));
    $baseSalary = floatval($body['base_salary'] ?? 0);
    $bonus      = floatval($body['bonus'] ?? 0);
    $deductions = floatval($body['deductions'] ?? 0);

    if (!$employeeId) {
        error_response('employee_id is required');
    }
    $empCheck = $pdo->prepare("SELECT id, salary FROM employees WHERE id = ? AND company_id = ?");
    $empCheck->execute([$employeeId, cid()]);
    $employee = $empCheck->fetch();
    if (!$employee) {
        error_response('Employee not found', 404);
    }

    $dup = $pdo->prepare("SELECT id FROM payroll WHERE company_id = ? AND employee_id = ? AND month = ? AND year = ? LIMIT 1");
    $dup->execute([cid(), $employeeId, $month, $year]);
    if ($dup->fetchColumn()) {
        error_response('A payroll record already exists for this employee and month', 409);
    }

    if ($baseSalary == 0.0 && $employee['salary']) {
        $baseSalary = (float)$employee['salary'];
    }
    $netPay = $baseSalary + $bonus - $deductions;

    $pdo->prepare(
        "INSERT INTO payroll (company_id, employee_id, month, year, base_salary, bonus, deductions, net_pay, status, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', NOW())"
    )->execute([cid(), $employeeId, $month, $year, $baseSalary, $bonus, $deductions, $netPay]);

    payroll_get_one((int)$pdo->lastInsertId(), $pdo);
}

/**
 * Work out one employee's pay for a month from attendance, leave and the payroll policy.
 * Returns [base, bonus, deductions, breakdown].
 */
function payroll_compute(PDO $pdo, array $emp, int $month, int $year): array {
    $pol   = payroll_policy($pdo);
    $salary = (float)$emp['salary'];
    $base  = $salary;
    if (!$pol['use_attendance']) return payroll_finish($pdo, $emp, $month, $year, $base, 0.0, 0.0, null);

    $now   = att_now($pdo);
    $today = $now->format('Y-m-d');
    $first = new DateTime(sprintf('%04d-%02d-01', $year, $month));
    $last  = (clone $first)->modify('last day of this month');
    $from  = $first->format('Y-m-d'); $to = $last->format('Y-m-d');
    $shift = att_shift($pdo, $emp);
    $eid   = (int)$emp['id'];

    // prefetch
    $att = [];
    $q = $pdo->prepare("SELECT * FROM attendance WHERE company_id = ? AND employee_id = ? AND date BETWEEN ? AND ?");
    $q->execute([cid(), $eid, $from, $to]);
    foreach ($q->fetchAll() as $r) $att[$r['date']] = $r;
    $hol = [];
    $q = $pdo->prepare("SELECT date FROM holidays WHERE company_id = ? AND date BETWEEN ? AND ?");
    $q->execute([cid(), $from, $to]);
    foreach ($q->fetchAll(PDO::FETCH_COLUMN) as $d) $hol[$d] = true;
    $leaves = [];                                   // date => paid(bool)
    $q = $pdo->prepare(
        "SELECT l.start_date, l.end_date, COALESCE(lt.paid, 1) AS paid FROM leaves l
         LEFT JOIN leave_types lt ON lt.company_id = l.company_id AND lt.code = l.type
         WHERE l.company_id = ? AND l.employee_id = ? AND l.status = 'approved' AND l.start_date <= ? AND l.end_date >= ?"
    );
    $q->execute([cid(), $eid, $to, $from]);
    foreach ($q->fetchAll() as $l) {
        for ($d = new DateTime(max($l['start_date'], $from)); $d->format('Y-m-d') <= min($l['end_date'], $to); $d->modify('+1 day')) {
            $leaves[$d->format('Y-m-d')] = (bool)$l['paid'];
        }
    }

    $trackFrom = att_tracking_start($pdo, $eid);
    $workdays = 0; $absent = 0; $half = 0; $lateMin = 0; $lateDays = 0; $otMin = 0; $unpaid = 0; $counted = 0;
    for ($d = clone $first; $d <= $last; $d->modify('+1 day')) {
        $ds = $d->format('Y-m-d');
        if (!att_is_workday($pdo, $shift, $ds) || isset($hol[$ds])) continue;
        $workdays++;
        if ($ds > $today) continue;
        $rec = $att[$ds] ?? null;
        if ($rec) {
            $counted++;
            if     ($rec['status'] === 'absent')   $absent++;
            elseif ($rec['status'] === 'half_day') $half++;
            elseif ($rec['status'] === 'late')     { $lateDays++; $lateMin += (int)$rec['late_minutes']; }
            $otMin += (int)$rec['overtime_minutes'];
            continue;
        }
        if (isset($leaves[$ds])) { if (!$leaves[$ds]) $unpaid++; continue; }
        if ($ds < $today && $trackFrom !== null && $ds >= $trackFrom) { $absent++; $counted++; }   // a finished working day with nothing recorded (only from the first sign-in)
    }
    // overtime on days off also counts
    foreach ($att as $ds => $rec) { if (!att_is_workday($pdo, $shift, $ds) || isset($hol[$ds])) $otMin += (int)$rec['overtime_minutes']; }

    $divisor = $pol['day_divisor'] === '30' ? 30 : max(1, $workdays);
    $daily   = $salary / $divisor;
    $hourly  = $daily / max(1, (float)$pol['shift_hours']);
    $lines = []; $ded = 0.0; $bonus = 0.0;
    $add = function (string $key, string $label, float $qty, float $amount) use (&$lines) {
        $lines[] = ['key' => $key, 'label' => $label, 'qty' => round($qty, 2), 'amount' => round($amount, 2)];
    };
    if ($pol['deduct_absent'] && $absent > 0)               { $a = $absent * $daily;                                $ded += $a; $add('absent', 'Absent days', $absent, -$a); }
    if ($pol['deduct_unpaid_leave'] && $unpaid > 0)         { $a = $unpaid * $daily;                                $ded += $a; $add('unpaid_leave', 'Unpaid leave days', $unpaid, -$a); }
    if ($half > 0 && $pol['half_day_fraction'] > 0)         { $a = $half * $daily * (float)$pol['half_day_fraction']; $ded += $a; $add('half_day', 'Half days', $half, -$a); }
    if ($pol['late_deduction'] === 'hourly' && $lateMin > 0){ $a = ($lateMin / 60) * $hourly;                       $ded += $a; $add('late', 'Late minutes', $lateMin, -$a); }
    if ($pol['overtime_enabled'] && $otMin > 0)             { $a = ($otMin / 60) * $hourly * (float)$pol['overtime_multiplier']; $bonus += $a; $add('overtime', 'Overtime (hours)', $otMin / 60, $a); }
    if ((float)$pol['perfect_attendance_bonus'] > 0 && $counted > 0 && $absent === 0 && $half === 0 && $lateDays === 0 && $unpaid === 0) {
        $a = (float)$pol['perfect_attendance_bonus']; $bonus += $a; $add('perfect', 'Perfect attendance bonus', 1, $a);
    }
    $ded = min($ded, $base);
    return payroll_finish($pdo, $emp, $month, $year, $base, round($bonus, 2), round($ded, 2), [
        'lines' => $lines,
        'stats' => ['working_days' => $workdays, 'absent_days' => $absent, 'half_days' => $half, 'late_days' => $lateDays, 'late_minutes' => $lateMin,
                    'overtime_minutes' => $otMin, 'unpaid_leave_days' => $unpaid, 'daily_rate' => round($daily, 2)],
    ]);
}

function payroll_preview(PDO $pdo): void {
    $id = intval($_GET['employee_id'] ?? 0);
    [$m, $y] = payroll_split_month($_GET['month'] ?? date('Y-m'));
    $y = $y ?? (int)date('Y');
    $e = att_employee_row($pdo, $id);
    if (!$e) error_response('Employee not found', 404);
    [$base, $bonus, $ded, $bd] = payroll_compute($pdo, $e, $m, $y);
    json_response(['success' => true, 'data' => ['base_salary' => $base, 'bonus' => $bonus, 'deductions' => $ded, 'net_pay' => max(0, $base + $bonus - $ded), 'breakdown' => $bd]]);
}

/** Create (or, with recalculate, refresh the pending) payslips for every active employee with a salary. */
function payroll_generate(array $body, PDO $pdo): void {
    [$month, $y] = payroll_split_month($body['month'] ?? date('Y-m'));
    $year = $y ?? intval($body['year'] ?? date('Y'));
    if ($month < 1 || $month > 12) error_response('Invalid month', 422);
    $recalc = !empty($body['recalculate']);

    $emps = $pdo->prepare(
        "SELECT e.*, s.name AS shift_name, s.start_time AS shift_start, s.end_time AS shift_end, s.days AS shift_days
         FROM employees e LEFT JOIN shifts s ON s.id = e.shift_id
         WHERE e.company_id = ? AND e.status != 'inactive' AND e.salary IS NOT NULL AND e.salary > 0"
    );
    $emps->execute([cid()]);
    $find = $pdo->prepare("SELECT id, status FROM payroll WHERE company_id = ? AND employee_id = ? AND month = ? AND year = ? LIMIT 1");
    $ins = $pdo->prepare(
        "INSERT INTO payroll (company_id, employee_id, month, year, base_salary, bonus, deductions, net_pay, breakdown, status, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', NOW())"
    );
    $upd = $pdo->prepare("UPDATE payroll SET base_salary = ?, bonus = ?, deductions = ?, net_pay = ?, breakdown = ? WHERE id = ? AND company_id = ?");
    $created = 0; $updated = 0;
    foreach ($emps->fetchAll() as $e) {
        $find->execute([cid(), $e['id'], $month, $year]);
        $ex = $find->fetch();
        if ($ex && (!$recalc || $ex['status'] !== 'pending')) continue;
        [$base, $bonus, $ded, $bd] = payroll_compute($pdo, $e, $month, $year);
        $net = max(0, $base + $bonus - $ded);
        $json = $bd ? json_encode($bd, JSON_UNESCAPED_UNICODE) : null;
        if ($ex) { $upd->execute([$base, $bonus, $ded, $net, $json, $ex['id'], cid()]); $updated++; }
        else     { $ins->execute([cid(), $e['id'], $month, $year, $base, $bonus, $ded, $net, $json]); $created++; }
    }
    audit($pdo, 'generate', 'payroll', null, ['month' => sprintf('%04d-%02d', $year, $month), 'created' => $created, 'updated' => $updated]);
    json_response(['success' => true, 'data' => ['created' => $created, 'updated' => $updated, 'month' => sprintf('%04d-%02d', $year, $month)]]);
}

function payroll_notify_paid(PDO $pdo, array $row): void {
    $label = sprintf('%04d-%02d', (int)$row['year'], (int)$row['month']);
    notify_employee($pdo, (int)$row['employee_id'], 'payslip', 'Your payslip is ready',
        "Your salary for $label has been paid.", ['payroll_id' => (int)$row['id']]);
}

function payroll_pay_all(array $body, PDO $pdo): void {
    [$month, $y] = payroll_split_month($body['month'] ?? date('Y-m'));
    $year = $y ?? intval($body['year'] ?? date('Y'));

    $rows = $pdo->prepare("SELECT id, employee_id, month, year FROM payroll WHERE company_id = ? AND month = ? AND year = ? AND status = 'pending'");
    $rows->execute([cid(), $month, $year]);
    $list = $rows->fetchAll();
    $pdo->prepare("UPDATE payroll SET status = 'paid', paid_at = NOW() WHERE company_id = ? AND month = ? AND year = ? AND status = 'pending'")
        ->execute([cid(), $month, $year]);
    foreach ($list as $r) payroll_notify_paid($pdo, $r);

    audit($pdo, 'pay_all', 'payroll', null, ['month' => sprintf('%04d-%02d', $year, $month), 'paid' => count($list)]);
    json_response(['success' => true, 'data' => ['paid' => count($list), 'month' => sprintf('%04d-%02d', $year, $month)]]);
}

function payroll_update(int $id, array $body, PDO $pdo): void {
    $check = $pdo->prepare("SELECT * FROM payroll WHERE id = ? AND company_id = ?");
    $check->execute([$id, cid()]);
    $current = $check->fetch();
    if (!$current) {
        error_response('Payroll record not found', 404);
    }

    if (array_key_exists('month', $body)) {
        [$um, $uy] = payroll_split_month($body['month']);
        $body['month'] = $um;
        if ($uy !== null) {
            $body['year'] = $uy;
        }
    }

    $fields = [];
    $params = [];
    foreach (['month', 'year', 'base_salary', 'bonus', 'deductions', 'status'] as $field) {
        if (array_key_exists($field, $body)) {
            $fields[] = "$field = ?";
            $params[]  = $body[$field];
        }
    }
    if (isset($body['status']) && !in_array($body['status'], ['pending', 'paid', 'cancelled'], true)) {
        error_response('Invalid status', 422);
    }

    $becamePaid = !empty($body['status']) && $body['status'] === 'paid' && $current['status'] !== 'paid';
    if ($becamePaid) {
        $fields[] = 'paid_at = ?';
        $params[]  = date('Y-m-d H:i:s');
    }

    if (isset($body['base_salary']) || isset($body['bonus']) || isset($body['deductions'])) {
        $base = floatval($body['base_salary'] ?? $current['base_salary']);
        $bon  = floatval($body['bonus']       ?? $current['bonus']);
        $ded  = floatval($body['deductions']  ?? $current['deductions']);
        $fields[] = 'net_pay = ?';
        $params[]  = $base + $bon - $ded;
    }

    if (empty($fields)) {
        error_response('No fields to update');
    }

    $params[] = $id;
    $params[] = cid();
    $pdo->prepare("UPDATE payroll SET " . implode(', ', $fields) . " WHERE id = ? AND company_id = ?")->execute($params);

    if ($becamePaid) payroll_notify_paid($pdo, $current);
    payroll_get_one($id, $pdo);
}

function payroll_delete(int $id, PDO $pdo): void {
    if (!in_company($pdo, 'payroll', $id)) {
        error_response('Payroll record not found', 404);
    }
    $pdo->prepare("DELETE FROM payroll WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
    json_response(['success' => true, 'message' => 'Payroll record deleted']);
}
