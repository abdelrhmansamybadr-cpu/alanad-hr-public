<?php
/**
 * Departments API handler (company-scoped)
 *
 *   GET    /departments                      list (with head + employee count)
 *   GET    /departments/{id}                 one department with its members
 *   POST   /departments                      {name, description?, head_id?}            (HR)
 *   PUT    /departments/{id}                 {name?, description?, head_id?}            (HR)
 *   DELETE /departments/{id}                                                            (HR)
 *   POST   /departments/{id}/members         {employee_ids: [1,2]}  move employees in  (HR)
 *   DELETE /departments/{id}/members/{eid}   take an employee out                      (HR)
 *
 * The head is an EMPLOYEE (head_id = employees.id). Members without a manager get the head as manager.
 */
function handle_departments(string $path, string $method, array $body): void {
    $pdo      = getDB();
    $segments = explode('/', $path);
    $id       = isset($segments[1]) && is_numeric($segments[1]) ? intval($segments[1]) : null;

    if ($id !== null && ($segments[2] ?? '') === 'members') {
        require_hr();
        if ($method === 'POST')                                      { departments_add_members($id, $body, $pdo); return; }
        if ($method === 'DELETE' && isset($segments[3]) && is_numeric($segments[3])) { departments_remove_member($id, intval($segments[3]), $pdo); return; }
        error_response('Method not allowed', 405);
    }

    if ($id !== null) {
        switch ($method) {
            case 'GET':    departments_get_one($id, $pdo); break;
            case 'PUT':    require_hr(); departments_update($id, $body, $pdo); break;
            case 'DELETE': require_hr(); departments_delete($id, $pdo); break;
            default:       error_response('Method not allowed', 405);
        }
    } else {
        switch ($method) {
            case 'GET':  departments_list($pdo); break;
            case 'POST': require_hr(); departments_create($body, $pdo); break;
            default:     error_response('Method not allowed', 405);
        }
    }
}

function departments_select(): string {
    return "SELECT d.*,
                   CONCAT(h.first_name, ' ', h.last_name) AS head_name,
                   h.avatar AS head_avatar, h.position AS head_position,
                   CONCAT(h.first_name, ' ', h.last_name) AS manager_name,
                   COUNT(DISTINCT e.id) AS employee_count
            FROM departments d
            LEFT JOIN employees h ON h.id = d.head_employee_id
            LEFT JOIN employees e ON e.department_id = d.id AND e.status != 'inactive'";
}

function departments_list(PDO $pdo): void {
    $stmt = $pdo->prepare(departments_select() . " WHERE (d.company_id = ? OR d.id IN (SELECT item_id FROM group_shares WHERE kind = 'department' AND target_company_id = ?)) GROUP BY d.id ORDER BY d.name");
    $stmt->execute([cid(), cid()]);
    $rows = $stmt->fetchAll();
    $counts = group_share_counts($pdo, 'department');
    $names = [];
    foreach ($rows as &$r) {
        if ((int)$r['company_id'] === cid()) { $r['shared_count'] = (int)($counts[$r['id']] ?? 0); continue; }
        $r['shared'] = true;
        $r['read_only'] = true;
        if (!isset($names[$r['company_id']])) { $n = $pdo->prepare("SELECT name FROM companies WHERE id = ?"); $n->execute([$r['company_id']]); $names[$r['company_id']] = (string)$n->fetchColumn(); }
        $r['shared_from'] = $names[$r['company_id']];
    }
    unset($r);
    json_response(['success' => true, 'data' => $rows]);
}

function departments_fetch(int $id, PDO $pdo): ?array {
    // this company's own department, or one shared into it
    $stmt = $pdo->prepare(departments_select() . " WHERE d.id = ? AND (d.company_id = ? OR d.id IN (SELECT item_id FROM group_shares WHERE kind = 'department' AND target_company_id = ?)) GROUP BY d.id");
    $stmt->execute([$id, cid(), cid()]);
    $d = $stmt->fetch() ?: null;
    if ($d && (int)$d['company_id'] !== cid()) {
        $n = $pdo->prepare("SELECT name FROM companies WHERE id = ?");
        $n->execute([$d['company_id']]);
        $d['shared'] = true;
        $d['read_only'] = true;
        $d['shared_from'] = (string)$n->fetchColumn();
    }
    return $d;
}

function departments_get_one(int $id, PDO $pdo): void {
    $dept = departments_fetch($id, $pdo);
    if (!$dept) error_response('Department not found', 404);

    $m = $pdo->prepare(
        "SELECT e.id, e.first_name, e.last_name, e.position, e.avatar, e.status, e.email, e.company_id, c.name AS company_name
         FROM employees e JOIN companies c ON c.id = e.company_id
         WHERE e.department_id = ? AND e.status != 'inactive' ORDER BY (e.company_id = ?) DESC, e.first_name, e.last_name"
    );
    $m->execute([$id, cid()]);
    $members = $m->fetchAll();
    foreach ($members as &$mem) { if ((int)$mem['company_id'] !== cid()) { $mem['shared'] = true; $mem['read_only'] = true; } }
    unset($mem);
    $dept['members'] = $members;
    json_response(['success' => true, 'data' => $dept]);
}

/** head_id -> employee id of this company, or null. */
function departments_valid_head(PDO $pdo, array $body): ?int {
    $raw = $body['head_id'] ?? $body['head_employee_id'] ?? null;
    $hid = int_or_null($raw);
    if ($hid === null) return null;
    // the head is one of this company's people, or someone another company of the group shares with it
    $shared = $pdo->prepare("SELECT 1 FROM group_shares WHERE kind = 'employee' AND item_id = ? AND target_company_id = ? LIMIT 1");
    $shared->execute([$hid, cid()]);
    if (!in_company($pdo, 'employees', $hid) && !$shared->fetchColumn()) error_response('The department head must be one of your people, or someone shared with your company', 422);
    return $hid;
}

/** Make `$headId` the head of `$deptId`: they join the department and lead members who have no manager yet. */
function departments_apply_head(PDO $pdo, int $deptId, ?int $headId): void {
    if ($headId === null) return;
    $pdo->prepare("UPDATE employees SET department_id = ? WHERE id = ? AND company_id = ?")->execute([$deptId, $headId, cid()]);
    $pdo->prepare("UPDATE employees SET manager_id = ? WHERE company_id = ? AND department_id = ? AND manager_id IS NULL AND id != ?")
        ->execute([$headId, cid(), $deptId, $headId]);
    notify_employee($pdo, $headId, 'department_head', 'You are now a department head', 'You were made head of a department. You can approve your team\'s requests.', ['department_id' => $deptId]);
}

function departments_create(array $body, PDO $pdo): void {
    $name = trim($body['name'] ?? '');
    if ($name === '') error_response('Department name is required');
    $head = departments_valid_head($pdo, $body);

    $pdo->prepare("INSERT INTO departments (company_id, name, description, head_employee_id) VALUES (?, ?, ?, ?)")
        ->execute([cid(), $name, $body['description'] ?? null, $head]);
    $id = (int)$pdo->lastInsertId();
    departments_apply_head($pdo, $id, $head);
    audit($pdo, 'create', 'department', $id, ['name' => $name, 'head' => $head]);
    departments_get_one($id, $pdo);
}

function departments_update(int $id, array $body, PDO $pdo): void {
    if (!in_company($pdo, 'departments', $id)) error_response('Department not found', 404);

    $fields = []; $params = [];
    if (array_key_exists('name', $body)) {
        if (trim((string)$body['name']) === '') error_response('Department name is required');
        $fields[] = 'name = ?'; $params[] = trim($body['name']);
    }
    if (array_key_exists('description', $body)) { $fields[] = 'description = ?'; $params[] = $body['description']; }
    $headTouched = array_key_exists('head_id', $body) || array_key_exists('head_employee_id', $body);
    $head = null;
    if ($headTouched) {
        // saving the form again with the same head is not a change (and must not fail for a head that is not "ours" any more)
        $cur = $pdo->prepare("SELECT head_employee_id FROM departments WHERE id = ? AND company_id = ?");
        $cur->execute([$id, cid()]);
        $curHead = $cur->fetchColumn();
        $sent = int_or_null($body['head_id'] ?? $body['head_employee_id'] ?? null);
        if ($sent !== null && $curHead !== false && (int)$curHead === $sent) { $headTouched = false; }
        else { $head = departments_valid_head($pdo, $body); $fields[] = 'head_employee_id = ?'; $params[] = $head; }
    }
    if (!$fields) error_response('No fields to update');

    $params[] = $id; $params[] = cid();
    $pdo->prepare("UPDATE departments SET " . implode(', ', $fields) . " WHERE id = ? AND company_id = ?")->execute($params);
    if ($headTouched) departments_apply_head($pdo, $id, $head);
    audit($pdo, 'update', 'department', $id, $body);
    departments_get_one($id, $pdo);
}

function departments_delete(int $id, PDO $pdo): void {
    if (!in_company($pdo, 'departments', $id)) error_response('Department not found', 404);
    // people of every company that was using it (own and shared-in) are taken out; its shares go with it
    $pdo->prepare("UPDATE employees SET department_id = NULL WHERE department_id = ?")->execute([$id]);
    $pdo->prepare("DELETE FROM group_shares WHERE kind = 'department' AND item_id = ?")->execute([$id]);
    $pdo->prepare("DELETE FROM departments WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
    audit($pdo, 'delete', 'department', $id);
    json_response(['success' => true, 'message' => 'Department deleted']);
}

function departments_add_members(int $id, array $body, PDO $pdo): void {
    $dept = departments_fetch($id, $pdo);
    if (!$dept) error_response('Department not found', 404);
    $ids = array_values(array_unique(array_filter(array_map('intval', (array)($body['employee_ids'] ?? [])), fn($i) => $i > 0)));
    if (!$ids) error_response('Choose at least one employee', 422);
    $moved = 0;
    foreach ($ids as $eid) {
        if (!in_company($pdo, 'employees', $eid)) continue;
        $pdo->prepare("UPDATE employees SET department_id = ? WHERE id = ? AND company_id = ?")->execute([$id, $eid, cid()]);
        if (!empty($dept['head_employee_id']) && (int)$dept['head_employee_id'] !== $eid) {
            $pdo->prepare("UPDATE employees SET manager_id = ? WHERE id = ? AND company_id = ? AND manager_id IS NULL")->execute([$dept['head_employee_id'], $eid, cid()]);
        }
        $moved++;
    }
    audit($pdo, 'add_members', 'department', $id, ['employee_ids' => $ids]);
    departments_get_one($id, $pdo);
}

function departments_remove_member(int $id, int $employeeId, PDO $pdo): void {
    $dept = departments_fetch($id, $pdo);
    if (!$dept) error_response('Department not found', 404);
    $pdo->prepare("UPDATE employees SET department_id = NULL WHERE id = ? AND company_id = ? AND department_id = ?")->execute([$employeeId, cid(), $id]);
    if ((int)($dept['head_employee_id'] ?? 0) === $employeeId) {
        $pdo->prepare("UPDATE departments SET head_employee_id = NULL WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
    }
    audit($pdo, 'remove_member', 'department', $id, ['employee_id' => $employeeId]);
    departments_get_one($id, $pdo);
}
