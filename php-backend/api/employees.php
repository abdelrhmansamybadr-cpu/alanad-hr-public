<?php
/**
 * Employees API handler (company-scoped)
 *
 *   POST /employees/{id}/promote     {type, position?, salary?, department_id?, effective_date?, note?}  (HR)
 *   GET  /employees/{id}/promotions  career history (HR or the employee)
 *   POST /employees/{id}/terminate   {date?, reason?}    POST /employees/{id}/reinstate   (HR)
 */
require_once __DIR__ . '/../helpers/policy.php';
function handle_employees(string $path, string $method, array $body): void {
    $pdo      = getDB();
    employees_apply_due_promotions($pdo);
    $segments = explode('/', $path);
    // segments[0] = 'employees', segments[1] = id or 'me'
    $sub = $segments[1] ?? '';

    // GET /employees/me  — current user's employee record
    if ($sub === 'me' && $method === 'GET') {
        employees_get_me(me(), $pdo);
        return;
    }

    $id = ($sub !== '' && is_numeric($sub)) ? intval($sub) : null;

    // POST /employees/{id}/invite — one-time code so the employee can activate / reset their app account
    if ($id !== null && ($segments[2] ?? '') === 'invite') {
        if ($method !== 'POST') error_response('Method not allowed', 405);
        require_hr();
        employees_invite($id, $pdo, $body);
        return;
    }

    if ($id !== null && isset($segments[2])) {
        $action = $segments[2];
        if ($action === 'promotions' && $method === 'GET') {
            if (!is_hr() && $id !== own_employee_id()) error_response('Forbidden. Insufficient permissions.', 403);
            employees_promotions($id, $pdo);
            return;
        }
        require_hr();
        if ($action === 'promote'   && $method === 'POST') { employees_promote($id, $body, $pdo); return; }
        if ($action === 'terminate' && $method === 'POST') { employees_terminate($id, $body, $pdo); return; }
        if ($action === 'reinstate' && $method === 'POST') { employees_reinstate($id, $pdo); return; }
        error_response('Not found', 404);
    }

    if ($id !== null) {
        switch ($method) {
            case 'GET':    employees_get_one($id, $pdo); break;
            case 'PUT':    require_hr(); employees_update($id, $body, $pdo); break;
            case 'DELETE': require_hr(); employees_delete($id, $pdo); break;
            default:       error_response('Method not allowed', 405);
        }
    } else {
        switch ($method) {
            case 'GET':    employees_list($pdo); break;
            case 'POST':   require_hr(); employees_create($body, $pdo); break;
            default:       error_response('Method not allowed', 405);
        }
    }
}

function employees_select(): string {
    return "SELECT e.*, d.name AS department_name, s.name AS shift_name,
                   CONCAT(m.first_name, ' ', m.last_name) AS manager_name
            FROM employees e
            LEFT JOIN departments d ON d.id = e.department_id
            LEFT JOIN shifts s ON s.id = e.shift_id
            LEFT JOIN employees m ON m.id = e.manager_id";
}

function employees_list(PDO $pdo): void {
    require_hr();
    $where  = ['e.company_id = ?'];
    $params = [cid()];

    if (!empty($_GET['department_id'])) {
        $where[]  = 'e.department_id = ?';
        $params[] = intval($_GET['department_id']);
    }
    if (!empty($_GET['status'])) {
        $where[]  = 'e.status = ?';
        $params[] = $_GET['status'];
    }
    if (!empty($_GET['q'])) {
        $where[]  = "(CONCAT(e.first_name, ' ', e.last_name) LIKE ? OR e.email LIKE ? OR e.position LIKE ?)";
        $like     = '%' . $_GET['q'] . '%';
        array_push($params, $like, $like, $like);
    }

    $stmt = $pdo->prepare(employees_select() . " WHERE " . implode(' AND ', $where) . " ORDER BY e.first_name, e.last_name");
    $stmt->execute($params);

    json_response(['success' => true, 'data' => $stmt->fetchAll()]);
}

function employees_fetch(int $id, PDO $pdo): ?array {
    $stmt = $pdo->prepare(employees_select() . " WHERE e.id = ? AND e.company_id = ?");
    $stmt->execute([$id, cid()]);
    $employee = $stmt->fetch();
    return $employee ?: null;
}

function employees_get_one(int $id, PDO $pdo): void {
    $employee = employees_fetch($id, $pdo);
    if (!$employee) {
        error_response('Employee not found', 404);
    }
    json_response(['success' => true, 'data' => $employee]);
}

function employees_get_me(array $currentUser, PDO $pdo): void {
    if (!$currentUser['employee_id']) {
        error_response('No employee record linked to this account', 404);
    }
    $employee = employees_fetch((int)$currentUser['employee_id'], $pdo);
    if (!$employee) {
        error_response('Employee not found', 404);
    }
    // Attach the assigned shift so the mobile app can enforce shift hours
    if (!empty($employee['shift_id'])) {
        $s = $pdo->prepare("SELECT id, name, start_time, end_time, color, days FROM shifts WHERE id = ? AND company_id = ?");
        $s->execute([$employee['shift_id'], cid()]);
        $employee['shift'] = $s->fetch() ?: null;
    }
    json_response(['success' => true, 'data' => $employee]);
}

/** Validate optional foreign keys so an employee can never point into another company. */
function employees_validate_refs(PDO $pdo, array $body): void {
    foreach (['department_id' => 'departments', 'shift_id' => 'shifts', 'manager_id' => 'employees'] as $field => $table) {
        if (!empty($body[$field]) && !in_company($pdo, $table, int_or_null($body[$field]))) {
            error_response("Invalid $field", 422);
        }
    }
}

function employees_create(array $body, PDO $pdo): void {
    $firstName = trim($body['first_name'] ?? '');
    $lastName  = trim($body['last_name'] ?? '');
    $email     = strtolower(trim($body['email'] ?? ''));

    if ($firstName === '' || $lastName === '' || $email === '') {
        error_response('first_name, last_name, and email are required');
    }
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
        error_response('Invalid email address', 422);
    }
    employees_validate_refs($pdo, $body);

    // Emails are unique across the whole platform (one email = one account)
    $check = $pdo->prepare("SELECT id FROM employees WHERE email = ? LIMIT 1");
    $check->execute([$email]);
    if ($check->fetch()) {
        error_response('An employee with this email already exists', 409);
    }

    $stmt = $pdo->prepare(
        "INSERT INTO employees
            (company_id, first_name, last_name, email, phone, position, department_id, shift_id, manager_id,
             status, start_date, salary, avatar, birth_date, gender, address, emergency_name, emergency_phone)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    );
    $stmt->execute([
        cid(),
        $firstName,
        $lastName,
        $email,
        $body['phone']          ?? null,
        $body['position']       ?? null,
        int_or_null($body['department_id'] ?? null),
        int_or_null($body['shift_id'] ?? null),
        int_or_null($body['manager_id'] ?? null),
        $body['status']         ?? 'active',
        !empty($body['start_date']) ? $body['start_date'] : date('Y-m-d'),
        isset($body['salary']) && $body['salary'] !== '' ? floatval($body['salary']) : null,
        $body['avatar']         ?? null,
        !empty($body['birth_date']) ? $body['birth_date'] : null,
        $body['gender']         ?? null,
        $body['address']        ?? null,
        $body['emergency_name'] ?? null,
        $body['emergency_phone'] ?? null,
    ]);

    $newId = (int)$pdo->lastInsertId();
    employees_default_manager($pdo, $newId);
    audit($pdo, 'create', 'employee', $newId, ['name' => "$firstName $lastName"]);
    notify_hr($pdo, 'employee_added', 'New employee added', "$firstName $lastName joined the team.", ['employee_id' => $newId], (int)me()['id']);

    // Give the new hire their onboarding checklist (never blocks creation)
    try { require_once __DIR__ . '/onboarding.php'; onboarding_start($pdo, $newId, false); } catch (Throwable $e) { error_log('onboarding: ' . $e->getMessage()); }

    // Return the employee together with the code they need to activate their app account
    $employee = employees_fetch($newId, $pdo);
    $employee['invite_code'] = invitation_create($pdo, $newId, 'activate');
    if (!empty($body['send_email'])) {
        require_once __DIR__ . '/../helpers/mailer.php';
        $employee['emailed'] = mail_send_code((string)$employee['email'], (string)(company_get($pdo, cid())['name'] ?? 'Al Anad HR'), 'activate', $employee['invite_code'], '7 days');
    }
    json_response(['success' => true, 'data' => $employee], 201);
}

function employees_invite(int $id, PDO $pdo, array $body = []): void {
    $employee = employees_fetch($id, $pdo);
    if (!$employee) error_response('Employee not found', 404);
    if ($employee['status'] === 'inactive') error_response('This employee is inactive', 422);

    $u = $pdo->prepare("SELECT 1 FROM users WHERE employee_id = ? AND company_id = ? AND role = 'employee' LIMIT 1");
    $u->execute([$id, cid()]);
    $hasAccount = (bool)$u->fetchColumn();

    $purpose = $hasAccount ? 'reset' : 'activate';
    $code    = invitation_create($pdo, $id, $purpose, $hasAccount ? 1 : 7);
    $emailed = null;
    if (!empty($body['send_email'])) {
        require_once __DIR__ . '/../helpers/mailer.php';
        $emailed = mail_send_code((string)$employee['email'], (string)(company_get($pdo, cid())['name'] ?? 'Al Anad HR'), $purpose, $code, $hasAccount ? 'a day' : '7 days');
    }
    json_response(['success' => true, 'data' => [
        'employee_id' => $id, 'email' => $employee['email'], 'purpose' => $purpose,
        'code' => $code, 'expires_in_days' => $hasAccount ? 1 : 7, 'emailed' => $emailed,
    ]]);
}

function employees_update(int $id, array $body, PDO $pdo): void {
    if (!in_company($pdo, 'employees', $id)) {
        error_response('Employee not found', 404);
    }
    employees_validate_refs($pdo, $body);
    if (isset($body['manager_id']) && (int)$body['manager_id'] === $id) {
        error_response('An employee cannot be their own manager', 422);
    }

    $fields = [];
    $params = [];

    $updatable = [
        'first_name', 'last_name', 'phone', 'position', 'status', 'start_date', 'avatar',
        'birth_date', 'gender', 'address', 'emergency_name', 'emergency_phone',
    ];
    foreach ($updatable as $field) {
        if (array_key_exists($field, $body)) {
            $fields[] = "$field = ?";
            $params[]  = $body[$field] === '' ? null : $body[$field];
        }
    }
    if (array_key_exists('email', $body)) {
        $email = strtolower(trim((string)$body['email']));
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) error_response('Invalid email address', 422);
        $dup = $pdo->prepare("SELECT id FROM employees WHERE email = ? AND id != ? LIMIT 1");
        $dup->execute([$email, $id]);
        if ($dup->fetch()) error_response('An employee with this email already exists', 409);
        $fields[] = 'email = ?';
        $params[]  = $email;
    }
    foreach (['department_id', 'shift_id', 'manager_id'] as $fk) {
        if (array_key_exists($fk, $body)) {
            $fields[] = "$fk = ?";
            $params[]  = int_or_null($body[$fk]);
        }
    }
    if (array_key_exists('salary', $body)) {
        $fields[] = 'salary = ?';
        $params[]  = $body['salary'] === '' || $body['salary'] === null ? null : floatval($body['salary']);
    }

    if (empty($fields)) {
        error_response('No fields to update');
    }

    $params[] = $id;
    $params[] = cid();
    $pdo->prepare("UPDATE employees SET " . implode(', ', $fields) . " WHERE id = ? AND company_id = ?")->execute($params);

    if (array_key_exists('department_id', $body) && !array_key_exists('manager_id', $body)) employees_default_manager($pdo, $id);
    audit($pdo, 'update', 'employee', $id, array_diff_key($body, ['avatar' => 1]));

    // A deactivated employee can no longer sign in
    if (isset($body['status']) && $body['status'] === 'inactive') {
        $pdo->prepare("UPDATE users SET status = 'disabled' WHERE employee_id = ? AND company_id = ? AND role = 'employee'")->execute([$id, cid()]);
    } elseif (isset($body['status']) && in_array($body['status'], ['active', 'on_leave'], true)) {
        $pdo->prepare("UPDATE users SET status = 'active' WHERE employee_id = ? AND company_id = ? AND role = 'employee' AND status = 'disabled'")->execute([$id, cid()]);
    }

    employees_get_one($id, $pdo);
}

function employees_delete(int $id, PDO $pdo): void {
    if (!in_company($pdo, 'employees', $id)) {
        error_response('Employee not found', 404);
    }

    employees_do_terminate($id, null, null, $pdo);
    json_response(['success' => true, 'message' => 'Employee deactivated']);
}


// ------------------------------------------------------------ career: promotions, exit

/** A member without a manager reports to the head of their department. */
function employees_default_manager(PDO $pdo, int $employeeId): void {
    $pdo->prepare(
        "UPDATE employees e JOIN departments d ON d.id = e.department_id AND d.company_id = e.company_id
         SET e.manager_id = d.head_employee_id
         WHERE e.id = ? AND e.company_id = ? AND e.manager_id IS NULL AND d.head_employee_id IS NOT NULL AND d.head_employee_id != e.id"
    )->execute([$employeeId, cid()]);
}

function employees_promotion_labels(): array {
    return ['promotion' => 'Promotion', 'raise' => 'Salary raise', 'transfer' => 'Transfer', 'demotion' => 'Role change'];
}

function employees_promotions(int $id, PDO $pdo): void {
    if (!employee_in_company($pdo, $id)) error_response('Employee not found', 404);
    $s = $pdo->prepare(
        "SELECT p.*, fd.name AS from_department_name, td.name AS to_department_name, u.name AS created_by_name
         FROM promotions p
         LEFT JOIN departments fd ON fd.id = p.from_department_id
         LEFT JOIN departments td ON td.id = p.to_department_id
         LEFT JOIN users u ON u.id = p.created_by
         WHERE p.company_id = ? AND p.employee_id = ? ORDER BY p.effective_date DESC, p.id DESC"
    );
    $s->execute([cid(), $id]);
    json_response(['success' => true, 'data' => $s->fetchAll()]);
}

/** Apply promotions/raises/transfers whose effective date has arrived. */
function employees_apply_due_promotions(PDO $pdo): void {
    if (empty($GLOBALS['HR_USER'])) return;
    $today = att_now($pdo)->format('Y-m-d');
    $s = $pdo->prepare("SELECT * FROM promotions WHERE company_id = ? AND applied = 0 AND effective_date <= ? LIMIT 50");
    $s->execute([cid(), $today]);
    foreach ($s->fetchAll() as $p) employees_apply_promotion($pdo, $p);
}

function employees_apply_promotion(PDO $pdo, array $p): void {
    $e = $pdo->prepare("SELECT position, salary, department_id FROM employees WHERE id = ? AND company_id = ?");
    $e->execute([$p['employee_id'], cid()]);
    $cur = $e->fetch();
    if (!$cur) return;
    $f = []; $a = [];
    if ($p['to_position'] !== null)      { $f[] = 'position = ?';      $a[] = $p['to_position']; }
    if ($p['to_salary'] !== null)        { $f[] = 'salary = ?';        $a[] = $p['to_salary']; }
    if ($p['to_department_id'] !== null) { $f[] = 'department_id = ?'; $a[] = $p['to_department_id']; }
    if ($f) {
        $a[] = $p['employee_id']; $a[] = cid();
        $pdo->prepare("UPDATE employees SET " . implode(', ', $f) . " WHERE id = ? AND company_id = ?")->execute($a);
        if ($p['to_department_id'] !== null) {
            $pdo->prepare("UPDATE employees SET manager_id = NULL WHERE id = ? AND company_id = ?")->execute([$p['employee_id'], cid()]);
            employees_default_manager($pdo, (int)$p['employee_id']);
        }
    }
    $pdo->prepare("UPDATE promotions SET applied = 1, from_position = ?, from_salary = ?, from_department_id = ? WHERE id = ? AND company_id = ?")
        ->execute([$cur['position'], $cur['salary'], $cur['department_id'], $p['id'], cid()]);

    $msg = [
        'promotion' => 'Congratulations! You have been promoted' . ($p['to_position'] ? ' to ' . $p['to_position'] : '') . '.',
        'raise'     => 'Good news: your salary has been updated.',
        'transfer'  => 'You have been transferred to a new department.',
        'demotion'  => 'Your role has been updated' . ($p['to_position'] ? ' to ' . $p['to_position'] : '') . '.',
    ][$p['type']] ?? 'Your job details were updated.';
    notify_employee($pdo, (int)$p['employee_id'], 'promotion', employees_promotion_labels()[$p['type']] ?? 'Update', $msg, ['promotion_id' => (int)$p['id']]);
}

function employees_promote(int $id, array $body, PDO $pdo): void {
    $emp = employees_fetch($id, $pdo);
    if (!$emp) error_response('Employee not found', 404);
    if ($emp['status'] === 'inactive') error_response('This employee is inactive', 422);

    $type = (string)($body['type'] ?? 'promotion');
    if (!isset(employees_promotion_labels()[$type])) error_response('Invalid type', 422);
    $position = isset($body['position']) && trim((string)$body['position']) !== '' ? trim((string)$body['position']) : null;
    $salary   = isset($body['salary']) && $body['salary'] !== '' ? floatval($body['salary']) : null;
    $dept     = int_or_null($body['department_id'] ?? null);
    if ($dept !== null && !in_company($pdo, 'departments', $dept)) error_response('Invalid department', 422);
    if ($salary !== null && $salary < 0) error_response('Salary cannot be negative', 422);
    if ($position === null && $salary === null && $dept === null) error_response('Enter a new position, salary or department', 422);

    $date = !empty($body['effective_date']) ? (string)$body['effective_date'] : att_now($pdo)->format('Y-m-d');
    $dd = DateTime::createFromFormat('Y-m-d', $date);
    if (!$dd || $dd->format('Y-m-d') !== $date) error_response('Date must be YYYY-MM-DD', 422);

    $pdo->prepare(
        "INSERT INTO promotions (company_id, employee_id, type, to_position, to_salary, to_department_id, effective_date, applied, note, created_by)
         VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?)"
    )->execute([cid(), $id, $type, $position, $salary, $dept, $date, isset($body['note']) ? mb_substr((string)$body['note'], 0, 1000) : null, (int)me()['id']]);
    $pid = (int)$pdo->lastInsertId();
    audit($pdo, $type, 'employee', $id, ['position' => $position, 'salary' => $salary, 'department_id' => $dept, 'date' => $date]);

    employees_apply_due_promotions($pdo);          // applies it right away when the date is today or earlier
    $s = $pdo->prepare("SELECT * FROM promotions WHERE id = ?");
    $s->execute([$pid]);
    json_response(['success' => true, 'data' => ['promotion' => $s->fetch(), 'employee' => employees_fetch($id, $pdo)]], 201);
}

function employees_do_terminate(int $id, ?string $date, ?string $reason, PDO $pdo): void {
    $date = $date ?: att_now($pdo)->format('Y-m-d');
    $pdo->prepare("UPDATE employees SET status = 'inactive', termination_date = ?, termination_reason = ? WHERE id = ? AND company_id = ?")->execute([$date, $reason, $id, cid()]);
    $pdo->prepare("UPDATE users SET status = 'disabled' WHERE employee_id = ? AND company_id = ? AND role = 'employee'")->execute([$id, cid()]);
    $pdo->prepare("DELETE FROM sessions WHERE user_id IN (SELECT id FROM users WHERE employee_id = ? AND company_id = ? AND role = 'employee')")->execute([$id, cid()]);
    // the people they managed move up to the leaver's manager
    $m = $pdo->prepare("SELECT manager_id FROM employees WHERE id = ? AND company_id = ?");
    $m->execute([$id, cid()]);
    $up = $m->fetchColumn();
    $pdo->prepare("UPDATE employees SET manager_id = ? WHERE manager_id = ? AND company_id = ?")->execute([$up ?: null, $id, cid()]);
    $pdo->prepare("UPDATE departments SET head_employee_id = NULL WHERE head_employee_id = ? AND company_id = ?")->execute([$id, cid()]);
    audit($pdo, 'terminate', 'employee', $id, ['date' => $date, 'reason' => $reason]);
}

function employees_terminate(int $id, array $body, PDO $pdo): void {
    if (!in_company($pdo, 'employees', $id)) error_response('Employee not found', 404);
    if ($id === own_employee_id()) error_response('You cannot end your own employment', 422);
    $date = !empty($body['date']) ? (string)$body['date'] : null;
    employees_do_terminate($id, $date, isset($body['reason']) ? mb_substr(trim((string)$body['reason']), 0, 1000) : null, $pdo);
    employees_get_one($id, $pdo);
}

function employees_reinstate(int $id, PDO $pdo): void {
    if (!in_company($pdo, 'employees', $id)) error_response('Employee not found', 404);
    $pdo->prepare("UPDATE employees SET status = 'active', termination_date = NULL, termination_reason = NULL WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
    $pdo->prepare("UPDATE users SET status = 'active' WHERE employee_id = ? AND company_id = ? AND role = 'employee'")->execute([$id, cid()]);
    audit($pdo, 'reinstate', 'employee', $id);
    employees_get_one($id, $pdo);
}
