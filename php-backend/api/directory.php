<?php
/**
 * Company directory and team (company-scoped)
 *
 *   GET /directory?q=          colleagues (name, position, department, contact) — visible to everyone
 *   GET /team                  the caller's direct reports with today's status (team leads and HR)
 */
require_once __DIR__ . '/attendance.php';

function handle_directory(string $path, string $method, array $body): void {
    if ($method !== 'GET') error_response('Method not allowed', 405);
    $pdo = getDB();

    $where  = ['e.company_id = ?', "e.status != 'inactive'"];
    $params = [cid()];
    if (!empty($_GET['q'])) {
        $where[] = "(CONCAT(e.first_name, ' ', e.last_name) LIKE ? OR e.position LIKE ? OR d.name LIKE ?)";
        $like = '%' . $_GET['q'] . '%';
        array_push($params, $like, $like, $like);
    }
    if (!empty($_GET['department_id'])) { $where[] = 'e.department_id = ?'; $params[] = intval($_GET['department_id']); }

    $s = $pdo->prepare(
        "SELECT e.id, e.first_name, e.last_name, e.position, e.email, e.phone, e.avatar, e.department_id,
                d.name AS department_name, e.manager_id
         FROM employees e LEFT JOIN departments d ON d.id = e.department_id
         WHERE " . implode(' AND ', $where) . " ORDER BY e.first_name, e.last_name LIMIT 500"
    );
    $s->execute($params);
    $rows = $s->fetchAll();
    // colleagues other companies of the group share with this company
    if (empty($_GET['department_id']) && !empty($_GET['include_shared'])) {
        $q = $pdo->prepare(
            "SELECT e.id, e.first_name, e.last_name, e.position, e.email, e.phone, e.avatar, e.department_id, d.name AS department_name, e.manager_id, c.name AS shared_from
             FROM group_shares g JOIN employees e ON e.id = g.item_id AND e.company_id = g.source_company_id
             JOIN companies c ON c.id = e.company_id LEFT JOIN departments d ON d.id = e.department_id
             WHERE g.kind = 'employee' AND g.target_company_id = ? AND e.status != 'inactive'"
            . (!empty($_GET['q']) ? " AND (CONCAT(e.first_name, ' ', e.last_name) LIKE ? OR e.position LIKE ? OR d.name LIKE ?)" : ''));
        $qp = [cid()];
        if (!empty($_GET['q'])) { $like = '%' . $_GET['q'] . '%'; array_push($qp, $like, $like, $like); }
        $q->execute($qp);
        foreach ($q->fetchAll() as $r) { $r['shared'] = true; $rows[] = $r; }
    }
    json_response(['success' => true, 'data' => $rows]);
}

function handle_team(string $path, string $method, array $body): void {
    if ($method !== 'GET') error_response('Method not allowed', 405);
    $pdo = getDB();
    $own = own_employee_id();
    if (!is_hr() && !has_direct_reports($pdo)) error_response('Forbidden. Insufficient permissions.', 403);

    $today = attendance_now($pdo)->format('Y-m-d');
    $s = $pdo->prepare(
        "SELECT e.id, e.first_name, e.last_name, e.position, e.avatar, e.email, e.phone,
                a.check_in, a.check_out, a.status AS attendance_status, a.late_minutes
         FROM employees e
         LEFT JOIN attendance a ON a.employee_id = e.id AND a.date = ? AND a.company_id = e.company_id
         WHERE e.company_id = ? AND e.status != 'inactive' AND e.manager_id = ?
         ORDER BY e.first_name"
    );
    $s->execute([$today, cid(), $own]);
    $rows = $s->fetchAll();
    foreach ($rows as &$r) {
        $leave = attendance_on_leave($pdo, (int)$r['id'], $today);
        $r['today'] = $r['attendance_status'] ?: ($leave ? 'on_leave' : 'absent');
        $r['leave_type'] = $leave['type_name'] ?? null;
    }
    unset($r);
    json_response(['success' => true, 'data' => $rows]);
}
