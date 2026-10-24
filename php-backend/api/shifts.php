<?php
/**
 * Shifts API handler (company-scoped)
 */
function handle_shifts(string $path, string $method, array $body): void {
    $pdo      = getDB();
    $segments = explode('/', $path);
    $sub      = $segments[1] ?? '';
    $sub2     = $segments[2] ?? '';

    // /shifts/assign/:employeeId  — DELETE to remove assignment
    if ($sub === 'assign' && $sub2 !== '' && is_numeric($sub2)) {
        if ($method !== 'DELETE') error_response('Method not allowed', 405);
        require_hr();
        shifts_unassign(intval($sub2), $pdo);
        return;
    }

    // /shifts/assign  — POST to assign a shift
    if ($sub === 'assign') {
        if ($method !== 'POST') error_response('Method not allowed', 405);
        require_hr();
        shifts_assign($body, $pdo);
        return;
    }

    $id = ($sub !== '' && is_numeric($sub)) ? intval($sub) : null;

    if ($id !== null) {
        switch ($method) {
            case 'GET':    shifts_get_one($id, $pdo); break;
            case 'PUT':    require_hr(); shifts_update($id, $body, $pdo); break;
            case 'DELETE': require_hr(); shifts_delete($id, $pdo); break;
            default:       error_response('Method not allowed', 405);
        }
    } else {
        switch ($method) {
            case 'GET':  shifts_list($pdo); break;
            case 'POST': require_hr(); shifts_create($body, $pdo); break;
            default:     error_response('Method not allowed', 405);
        }
    }
}

function shifts_select(): string {
    return "SELECT s.*, COUNT(DISTINCT e.id) AS assigned_employees
            FROM shifts s
            LEFT JOIN employees e ON e.shift_id = s.id AND e.status != 'inactive'";
}

/** Attach `employees` (who works this shift) to shift rows. */
function shifts_with_employees(PDO $pdo, array $rows): array {
    if (!$rows) return $rows;
    $s = $pdo->prepare("SELECT id, first_name, last_name, position, avatar, shift_id FROM employees WHERE company_id = ? AND shift_id IS NOT NULL AND status != 'inactive' ORDER BY first_name");
    $s->execute([cid()]);
    $by = [];
    foreach ($s->fetchAll() as $e) { $by[$e['shift_id']][] = ['id' => (int)$e['id'], 'first_name' => $e['first_name'], 'last_name' => $e['last_name'], 'position' => $e['position'] ?? '', 'avatar' => $e['avatar']]; }
    foreach ($rows as &$r) { $r['employees'] = $by[$r['id']] ?? []; }
    unset($r);
    return $rows;
}

function shifts_list(PDO $pdo): void {
    $stmt = $pdo->prepare(shifts_select() . " WHERE s.company_id = ? GROUP BY s.id ORDER BY s.name");
    $stmt->execute([cid()]);
    json_response(['success' => true, 'data' => shifts_with_employees($pdo, $stmt->fetchAll())]);
}

function shifts_get_one(int $id, PDO $pdo): void {
    $stmt = $pdo->prepare(shifts_select() . " WHERE s.id = ? AND s.company_id = ? GROUP BY s.id");
    $stmt->execute([$id, cid()]);
    $shift = $stmt->fetch();

    if (!$shift) {
        error_response('Shift not found', 404);
    }
    json_response(['success' => true, 'data' => shifts_with_employees($pdo, [$shift])[0]]);
}

function shifts_create(array $body, PDO $pdo): void {
    $name      = trim($body['name'] ?? '');
    $startTime = $body['start_time'] ?? '';
    $endTime   = $body['end_time'] ?? '';

    if ($name === '' || $startTime === '' || $endTime === '') {
        error_response('name, start_time, and end_time are required');
    }

    $stmt = $pdo->prepare(
        "INSERT INTO shifts (company_id, name, start_time, end_time, color, description, days, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, NOW())"
    );
    $stmt->execute([
        cid(),
        $name,
        $startTime,
        $endTime,
        $body['color']       ?? '#3B82F6',
        $body['description'] ?? null,
        $body['days']        ?? 'mon,tue,wed,thu,fri',
    ]);

    shifts_get_one((int)$pdo->lastInsertId(), $pdo);
}

function shifts_update(int $id, array $body, PDO $pdo): void {
    if (!in_company($pdo, 'shifts', $id)) {
        error_response('Shift not found', 404);
    }

    $fields = [];
    $params = [];

    foreach (['name', 'start_time', 'end_time', 'color', 'description', 'days'] as $field) {
        if (array_key_exists($field, $body)) {
            $fields[] = "$field = ?";
            $params[]  = $body[$field];
        }
    }

    if (empty($fields)) {
        error_response('No fields to update');
    }

    $params[] = $id;
    $params[] = cid();
    $pdo->prepare("UPDATE shifts SET " . implode(', ', $fields) . " WHERE id = ? AND company_id = ?")->execute($params);
    shifts_get_one($id, $pdo);
}

function shifts_delete(int $id, PDO $pdo): void {
    if (!in_company($pdo, 'shifts', $id)) {
        error_response('Shift not found', 404);
    }

    $pdo->prepare("DELETE FROM employee_shifts WHERE shift_id = ?")->execute([$id]);
    $pdo->prepare("UPDATE employees SET shift_id = NULL WHERE shift_id = ? AND company_id = ?")->execute([$id, cid()]);
    $pdo->prepare("DELETE FROM shifts WHERE id = ? AND company_id = ?")->execute([$id, cid()]);

    json_response(['success' => true, 'message' => 'Shift deleted']);
}

function shifts_assign(array $body, PDO $pdo): void {
    $employeeId = intval($body['employee_id'] ?? 0);
    $shiftId    = intval($body['shift_id'] ?? 0);

    if (!$employeeId || !$shiftId) {
        error_response('employee_id and shift_id are required');
    }
    if (!in_company($pdo, 'employees', $employeeId)) {
        error_response('Employee not found', 404);
    }
    if (!in_company($pdo, 'shifts', $shiftId)) {
        error_response('Shift not found', 404);
    }

    $pdo->prepare(
        "INSERT INTO employee_shifts (employee_id, shift_id, assigned_at)
         VALUES (?, ?, NOW())
         ON DUPLICATE KEY UPDATE shift_id = VALUES(shift_id), assigned_at = NOW()"
    )->execute([$employeeId, $shiftId]);

    $pdo->prepare("UPDATE employees SET shift_id = ? WHERE id = ? AND company_id = ?")->execute([$shiftId, $employeeId, cid()]);
    notify_employee($pdo, $employeeId, 'shift_assigned', 'New shift assigned', 'Your work shift was updated. Open the app to see your schedule.', ['shift_id' => $shiftId]);

    $row = $pdo->prepare(
        "SELECT es.*, CONCAT(e.first_name, ' ', e.last_name) AS employee_name, s.name AS shift_name
         FROM employee_shifts es
         JOIN employees e ON e.id = es.employee_id
         JOIN shifts s ON s.id = es.shift_id
         WHERE es.employee_id = ? AND e.company_id = ?"
    );
    $row->execute([$employeeId, cid()]);

    json_response(['success' => true, 'data' => $row->fetch()]);
}

function shifts_unassign(int $employeeId, PDO $pdo): void {
    if (!in_company($pdo, 'employees', $employeeId)) {
        error_response('Employee not found', 404);
    }
    $pdo->prepare("DELETE FROM employee_shifts WHERE employee_id = ?")->execute([$employeeId]);
    $pdo->prepare("UPDATE employees SET shift_id = NULL WHERE id = ? AND company_id = ?")->execute([$employeeId, cid()]);
    json_response(['success' => true, 'message' => 'Shift assignment removed']);
}
