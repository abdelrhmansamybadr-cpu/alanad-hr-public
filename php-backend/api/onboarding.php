<?php
/**
 * Onboarding checklists (company-scoped)
 *
 *   GET    /onboarding/templates                 the company's standard checklist (HR)
 *   POST   /onboarding/templates                 {title, description?, owner, due_days}        (HR)
 *   PUT    /onboarding/templates/{id}            (HR)        DELETE /onboarding/templates/{id}  (HR)
 *   GET    /onboarding/me                        my tasks + progress
 *   GET    /onboarding/overview                  everybody still onboarding (HR)
 *   GET    /onboarding/employee/{id}             one person's checklist (HR / their manager)
 *   POST   /onboarding/employee/{id}/start       build the checklist from the templates (HR)
 *   POST   /onboarding/employee/{id}/tasks       {title, description?, owner, due_date?}      (HR)
 *   PUT    /onboarding/tasks/{id}                {done: bool} (owner of the task or HR)
 *   DELETE /onboarding/tasks/{id}                (HR)
 */
require_once __DIR__ . '/../helpers/policy.php';

function onboarding_default_templates(): array {
    return [
        ['Read and sign your employment contract', 'Check the details and confirm with HR.', 'employee', 1, 'contract'],
        ['Complete your personal details', 'Ask HR to correct anything wrong from Me → Personal information.', 'employee', 2, 'details'],
        ['Upload your ID and required documents', 'Documents → upload each required file.', 'employee', 3, 'documents'],
        ['Set up your work account and equipment', 'Laptop, email and system access.', 'hr', 2, null],
        ['Add the employee to payroll', 'Confirm salary and bank details.', 'hr', 5, 'payroll'],
        ['Meet your manager and team', 'A short intro on the first days.', 'employee', 3, 'team'],
        ['Read the company policies', 'Attendance, leave and conduct.', 'employee', 7, 'policies'],
        ['Turn on notifications and check in once from the app', 'Try the attendance check-in.', 'employee', 2, 'checkin'],
    ];
}

/** Make sure the company has a template list (seeded once). */
function onboarding_templates_ensure(PDO $pdo): void {
    $c = $pdo->prepare("SELECT COUNT(*) FROM onboarding_templates WHERE company_id = ?");
    $c->execute([cid()]);
    if ((int)$c->fetchColumn() > 0) return;
    $ins = $pdo->prepare("INSERT INTO onboarding_templates (company_id, title, description, owner, due_days, sort_order, auto_key) VALUES (?,?,?,?,?,?,?)");
    foreach (onboarding_default_templates() as $i => $t) $ins->execute([cid(), $t[0], $t[1], $t[2], $t[3], $i, $t[4]]);
}

/** Create the checklist for a new employee (no-op if they already have tasks). */
function onboarding_start(PDO $pdo, int $employeeId, bool $notify = true): int {
    $has = $pdo->prepare("SELECT COUNT(*) FROM onboarding_tasks WHERE company_id = ? AND employee_id = ?");
    $has->execute([cid(), $employeeId]);
    if ((int)$has->fetchColumn() > 0) return 0;
    onboarding_templates_ensure($pdo);
    $t = $pdo->prepare("SELECT * FROM onboarding_templates WHERE company_id = ? AND is_active = 1 ORDER BY sort_order, id");
    $t->execute([cid()]);
    $today = att_now($pdo);
    $ins = $pdo->prepare("INSERT INTO onboarding_tasks (company_id, employee_id, title, description, owner, due_date, sort_order, auto_key) VALUES (?,?,?,?,?,?,?,?)");
    $n = 0;
    foreach ($t->fetchAll() as $i => $row) {
        $due = (clone $today)->modify('+' . (int)$row['due_days'] . ' days')->format('Y-m-d');
        $ins->execute([cid(), $employeeId, $row['title'], $row['description'], $row['owner'], $due, $i, $row['auto_key'] ?? null]);
        $n++;
    }
    if ($n && $notify) {
        notify_employee($pdo, $employeeId, 'onboarding', 'Welcome! Your checklist is ready', "You have $n steps to get started. Open Home → Getting started.", ['employee_id' => $employeeId]);
    }
    return $n;
}

function handle_onboarding(string $path, string $method, array $body): void {
    $pdo = getDB();
    $seg = explode('/', $path);
    $sub = $seg[1] ?? '';
    $id  = isset($seg[2]) && ctype_digit($seg[2]) ? intval($seg[2]) : null;

    if ($sub === 'me' && $method === 'GET') {
        $eid = own_employee_id();
        if ($eid <= 0) error_response('No employee record linked to this account', 404);
        onboarding_start($pdo, $eid, false);           // anyone created before this feature gets a checklist on first look
        json_response(['success' => true, 'data' => onboarding_view($pdo, $eid)]);
    }
    if ($sub === 'event' && $method === 'POST') { onboarding_event($body, $pdo); }
    if ($sub === 'tasks' && $id !== null) {
        if ($method === 'PUT')    { onboarding_task_update($id, $body, $pdo); }
        if ($method === 'DELETE') { require_hr(); onboarding_task_delete($id, $pdo); }
        error_response('Method not allowed', 405);
    }
    require_hr();
    switch ($sub) {
        case 'templates':
            onboarding_templates_ensure($pdo);
            if ($method === 'GET' && $id === null) {
                $s = $pdo->prepare("SELECT * FROM onboarding_templates WHERE company_id = ? ORDER BY sort_order, id");
                $s->execute([cid()]);
                json_response(['success' => true, 'data' => $s->fetchAll()]);
            }
            if ($method === 'POST' && $id === null) onboarding_template_save(null, $body, $pdo);
            if ($method === 'PUT' && $id !== null)    onboarding_template_save($id, $body, $pdo);
            if ($method === 'DELETE' && $id !== null) {
                $pdo->prepare("DELETE FROM onboarding_templates WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
                audit($pdo, 'delete', 'onboarding_template', $id);
                json_response(['success' => true, 'message' => 'Deleted']);
            }
            break;
        case 'start-all':                    // give every active employee who has no checklist yet the standard one
            if ($method !== 'POST') error_response('Method not allowed', 405);
            $e = $pdo->prepare("SELECT id FROM employees WHERE company_id = ? AND status != 'inactive'
                                AND id NOT IN (SELECT employee_id FROM onboarding_tasks WHERE company_id = ?)");
            $e->execute([cid(), cid()]);
            $count = 0;
            foreach ($e->fetchAll(PDO::FETCH_COLUMN) as $eid) { if (onboarding_start($pdo, (int)$eid, false) > 0) $count++; }
            audit($pdo, 'start_all', 'onboarding', null, ['employees' => $count]);
            json_response(['success' => true, 'data' => ['started' => $count]]);
            break;
        case 'overview':
            if ($method !== 'GET') error_response('Method not allowed', 405);
            onboarding_overview($pdo);
            break;
        case 'employee':
            if ($id === null || !employee_in_company($pdo, $id)) error_response('Employee not found', 404);
            $act = $seg[3] ?? '';
            if ($method === 'GET' && $act === '') json_response(['success' => true, 'data' => onboarding_view($pdo, $id)]);
            if ($method === 'POST' && $act === 'start') {
                $n = onboarding_start($pdo, $id);
                audit($pdo, 'start', 'onboarding', $id, ['tasks' => $n]);
                json_response(['success' => true, 'data' => onboarding_view($pdo, $id)], 201);
            }
            if ($method === 'POST' && $act === 'tasks') onboarding_task_add($id, $body, $pdo);
            break;
    }
    error_response('Not found', 404);
}

/** The step really happened? (checked by the system from real data, never from a tick) */
function onboarding_condition(PDO $pdo, int $eid, string $key): bool {
    switch ($key) {
        case 'contract': case 'details': case 'policies': case 'team':
            $q = $pdo->prepare("SELECT 1 FROM onboarding_events WHERE employee_id = ? AND ev_key = ?");
            $q->execute([$eid, $key]);
            return (bool)$q->fetchColumn();
        case 'documents':
            $need = (int)$pdo->query("SELECT COUNT(*) FROM required_document_types WHERE company_id = " . (int)cid())->fetchColumn();
            $q = $pdo->prepare("SELECT COUNT(DISTINCT document_type_id) FROM employee_documents WHERE employee_id = ?");
            $q->execute([$eid]);
            return (int)$q->fetchColumn() >= max(1, $need);
        case 'payroll':
            $q = $pdo->prepare("SELECT salary FROM employees WHERE id = ? AND company_id = ?");
            $q->execute([$eid, cid()]);
            return (float)$q->fetchColumn() > 0;
        case 'checkin':
            $q = $pdo->prepare("SELECT 1 FROM attendance WHERE employee_id = ? AND check_in IS NOT NULL LIMIT 1");
            $q->execute([$eid]);
            return (bool)$q->fetchColumn();
    }
    return false;
}

/** Tick every open step whose real-world condition is met. done_by stays NULL = "the system did it". */
function onboarding_autocheck(PDO $pdo, int $eid): void {
    $s = $pdo->prepare("SELECT id, auto_key FROM onboarding_tasks WHERE company_id = ? AND employee_id = ? AND done = 0 AND auto_key IS NOT NULL");
    $s->execute([cid(), $eid]);
    $flipped = 0;
    $up = $pdo->prepare("UPDATE onboarding_tasks SET done = 1, done_at = NOW(), done_by = NULL WHERE id = ? AND company_id = ?");
    foreach ($s->fetchAll() as $t) {
        if (onboarding_condition($pdo, $eid, (string)$t['auto_key'])) { $up->execute([(int)$t['id'], cid()]); $flipped++; }
    }
    if ($flipped) onboarding_notify_if_complete($pdo, $eid, false);
}

function onboarding_notify_if_complete(PDO $pdo, int $eid, bool $tickedByEmployee): void {
    $c = $pdo->prepare("SELECT COUNT(*) AS n, COALESCE(SUM(done), 0) AS d FROM onboarding_tasks WHERE company_id = ? AND employee_id = ?");
    $c->execute([cid(), $eid]);
    $r = $c->fetch();
    if ((int)$r['n'] === 0 || (int)$r['n'] !== (int)$r['d']) return;
    $n = $pdo->prepare("SELECT CONCAT(first_name, ' ', last_name) FROM employees WHERE id = ?");
    $n->execute([$eid]);
    notify_hr($pdo, 'onboarding', 'Onboarding complete', $n->fetchColumn() . ' finished every onboarding step.', ['employee_id' => $eid], (int)(me()['id'] ?? 0));
    if (!$tickedByEmployee) notify_employee($pdo, $eid, 'onboarding', 'All set!', 'Your onboarding checklist is complete. Welcome aboard!', null);
}

function onboarding_view(PDO $pdo, int $employeeId): array {
    onboarding_autocheck($pdo, $employeeId);
    $s = $pdo->prepare("SELECT t.*, u.name AS done_by_name FROM onboarding_tasks t LEFT JOIN users u ON u.id = t.done_by
                        WHERE t.company_id = ? AND t.employee_id = ? ORDER BY t.done, t.sort_order, t.id");
    $s->execute([cid(), $employeeId]);
    $tasks = $s->fetchAll();
    foreach ($tasks as &$t) { if ((int)$t['done'] === 1 && $t['done_by'] === null) $t['done_by_name'] = 'System'; }
    unset($t);
    $done = count(array_filter($tasks, fn($t) => (int)$t['done'] === 1));
    return ['employee_id' => $employeeId, 'total' => count($tasks), 'done' => $done, 'complete' => count($tasks) > 0 && $done === count($tasks), 'tasks' => $tasks];
}

/** POST /onboarding/event {key}: the app reports that the employee really did something (signed, read, opened). */
function onboarding_event(array $body, PDO $pdo): void {
    $eid = own_employee_id();
    if ($eid <= 0) error_response('No employee record linked to this account', 404);
    $key = (string)($body['key'] ?? '');
    if (!in_array($key, ['contract', 'details', 'policies', 'team'], true)) error_response('Unknown step', 422);
    $pdo->prepare("INSERT IGNORE INTO onboarding_events (company_id, employee_id, ev_key) VALUES (?,?,?)")->execute([cid(), $eid, $key]);
    json_response(['success' => true, 'data' => onboarding_view($pdo, $eid)]);
}

function onboarding_overview(PDO $pdo): void {
    $s = $pdo->prepare(
        "SELECT e.id AS employee_id, CONCAT(e.first_name, ' ', e.last_name) AS name, e.avatar, e.position, d.name AS department_name,
                COUNT(t.id) AS total, COALESCE(SUM(t.done), 0) AS done, MIN(CASE WHEN t.done = 0 THEN t.due_date END) AS next_due,
                COALESCE(SUM(t.done = 0 AND t.due_date IS NOT NULL AND t.due_date < ?), 0) AS overdue
         FROM employees e JOIN onboarding_tasks t ON t.employee_id = e.id AND t.company_id = e.company_id
         LEFT JOIN departments d ON d.id = e.department_id
         WHERE e.company_id = ? AND e.status != 'inactive' GROUP BY e.id ORDER BY (COALESCE(SUM(t.done),0) = COUNT(t.id)), name"
    );
    $s->execute([att_now($pdo)->format('Y-m-d'), cid()]);
    json_response(['success' => true, 'data' => $s->fetchAll()]);
}

function onboarding_template_save(?int $id, array $body, PDO $pdo): void {
    $title = trim((string)($body['title'] ?? ''));
    if ($title === '' || mb_strlen($title) > 200) error_response('A short title is required', 422);
    $owner = ($body['owner'] ?? 'employee') === 'hr' ? 'hr' : 'employee';
    $days  = max(0, min(365, (int)($body['due_days'] ?? 7)));
    $active = array_key_exists('is_active', $body) ? (int)!!$body['is_active'] : 1;
    if ($id === null) {
        onboarding_templates_ensure($pdo);
        $max = $pdo->prepare("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM onboarding_templates WHERE company_id = ?");
        $max->execute([cid()]);
        $pdo->prepare("INSERT INTO onboarding_templates (company_id, title, description, owner, due_days, sort_order, is_active) VALUES (?,?,?,?,?,?,?)")
            ->execute([cid(), $title, $body['description'] ?? null, $owner, $days, (int)$max->fetchColumn(), $active]);
        $id = (int)$pdo->lastInsertId();
    } else {
        if (!in_company($pdo, 'onboarding_templates', $id)) error_response('Template not found', 404);
        $pdo->prepare("UPDATE onboarding_templates SET title = ?, description = ?, owner = ?, due_days = ?, is_active = ? WHERE id = ? AND company_id = ?")
            ->execute([$title, $body['description'] ?? null, $owner, $days, $active, $id, cid()]);
    }
    audit($pdo, 'save', 'onboarding_template', $id, ['title' => $title]);
    $s = $pdo->prepare("SELECT * FROM onboarding_templates WHERE id = ?");
    $s->execute([$id]);
    json_response(['success' => true, 'data' => $s->fetch()], 201);
}

function onboarding_task_add(int $employeeId, array $body, PDO $pdo): void {
    $title = trim((string)($body['title'] ?? ''));
    if ($title === '' || mb_strlen($title) > 200) error_response('A short title is required', 422);
    $owner = ($body['owner'] ?? 'employee') === 'hr' ? 'hr' : 'employee';
    $due = !empty($body['due_date']) ? (string)$body['due_date'] : null;
    if ($due !== null) { $d = DateTime::createFromFormat('Y-m-d', $due); if (!$d || $d->format('Y-m-d') !== $due) error_response('Date must be YYYY-MM-DD', 422); }
    $pdo->prepare("INSERT INTO onboarding_tasks (company_id, employee_id, title, description, owner, due_date, sort_order) VALUES (?,?,?,?,?,?,999)")
        ->execute([cid(), $employeeId, $title, $body['description'] ?? null, $owner, $due]);
    if ($owner === 'employee') notify_employee($pdo, $employeeId, 'onboarding', 'New task for you', $title, ['employee_id' => $employeeId]);
    json_response(['success' => true, 'data' => onboarding_view($pdo, $employeeId)], 201);
}

function onboarding_task_update(int $id, array $body, PDO $pdo): void {
    $s = $pdo->prepare("SELECT * FROM onboarding_tasks WHERE id = ? AND company_id = ?");
    $s->execute([$id, cid()]);
    $t = $s->fetch();
    if (!$t) error_response('Task not found', 404);
    $mine = (int)$t['employee_id'] === own_employee_id();
    if (!is_hr()) {
        if (!$mine || $t['owner'] !== 'employee') error_response('Forbidden. Insufficient permissions.', 403);
        if (!empty($t['auto_key'])) error_response('This step is completed automatically once you really do it.', 403);
    }
    // HR can also edit the task itself (title, note, owner, due date)
    if (is_hr()) {
        $sets = []; $vals = [];
        if (array_key_exists('title', $body)) {
            $title = trim((string)$body['title']);
            if ($title === '' || mb_strlen($title) > 200) error_response('A short title is required', 422);
            $sets[] = 'title = ?'; $vals[] = $title;
        }
        if (array_key_exists('description', $body)) { $sets[] = 'description = ?'; $vals[] = trim((string)$body['description']) ?: null; }
        if (array_key_exists('owner', $body))       { $sets[] = 'owner = ?';       $vals[] = $body['owner'] === 'hr' ? 'hr' : 'employee'; }
        if (array_key_exists('due_date', $body)) {
            $due = $body['due_date'] === null || $body['due_date'] === '' ? null : (string)$body['due_date'];
            if ($due !== null) { $d = DateTime::createFromFormat('Y-m-d', $due); if (!$d || $d->format('Y-m-d') !== $due) error_response('Date must be YYYY-MM-DD', 422); }
            $sets[] = 'due_date = ?'; $vals[] = $due;
        }
        if ($sets) {
            $vals[] = $id; $vals[] = cid();
            $pdo->prepare('UPDATE onboarding_tasks SET ' . implode(', ', $sets) . ' WHERE id = ? AND company_id = ?')->execute($vals);
        }
    }
    $done = !empty($body['done']) ? 1 : 0;
    if (array_key_exists('done', $body)) {
        $pdo->prepare("UPDATE onboarding_tasks SET done = ?, done_at = IF(?, NOW(), NULL), done_by = IF(?, ?, NULL) WHERE id = ? AND company_id = ?")
            ->execute([$done, $done, $done, (int)me()['id'], $id, cid()]);
    }
    $view = onboarding_view($pdo, (int)$t['employee_id']);
    if ($done && $view['complete']) onboarding_notify_if_complete($pdo, (int)$t['employee_id'], $mine);
    json_response(['success' => true, 'data' => $view]);
}

function onboarding_task_delete(int $id, PDO $pdo): void {
    $s = $pdo->prepare("SELECT employee_id FROM onboarding_tasks WHERE id = ? AND company_id = ?");
    $s->execute([$id, cid()]);
    $eid = $s->fetchColumn();
    if (!$eid) error_response('Task not found', 404);
    $pdo->prepare("DELETE FROM onboarding_tasks WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
    json_response(['success' => true, 'data' => onboarding_view($pdo, (int)$eid)]);
}
