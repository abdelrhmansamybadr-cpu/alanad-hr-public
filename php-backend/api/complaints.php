<?php
/**
 * Complaints (feature `complaints`): a team head files a complaint about a member of the team or to HR; HR answers,
 * solves it or sends it up to the owner so both can follow the same problem.
 *
 *   GET  /complaints[?status=]            head: the ones I filed;  HR: every complaint of the company
 *   GET  /complaints/team                 head: my team (people I may complain about)
 *   GET  /complaints/owner[?status=]      owner / group Super Admin: complaints sent up to them (companies in their scope)
 *   GET  /complaints/{id}                 one complaint with its whole thread
 *   POST /complaints  {kind: member|hr, target_employee_id?, subject, body, severity?}     a team head
 *   PUT  /complaints/{id}  {action: comment, note}                         author, HR, owner (when sent up)
 *   PUT  /complaints/{id}  {action: respond, status: in_review|resolved|dismissed, note}   HR (or the owner once it is sent up)
 *   PUT  /complaints/{id}  {action: escalate, note}                        HR only: sends it to the owner
 *
 * Privacy: the person complained about never sees the complaint (employees get no list at all). Everything said on
 * a complaint is kept in complaint_events, in order, with who said it and when.
 */
const COMPLAINT_SEVERITY = ['low', 'normal', 'high'];

function handle_complaints(string $path, string $method, array $body): void {
    $pdo = getDB();
    $seg = explode('/', $path);
    $a = $seg[1] ?? '';
    $owner = owner_scope($pdo);

    if ($a === 'owner') {
        if ($method !== 'GET') error_response('Method not allowed', 405);
        if ($owner === null) error_response('Forbidden. Insufficient permissions.', 403);
        complaints_owner_list($pdo, $owner);
    }
    // everything else follows the company's switch (the owner may still open one that was sent up to them)
    $isId = ctype_digit($a);
    if (!($isId && $owner !== null && !feature_enabled($pdo, 'complaints'))) require_feature($pdo, 'complaints');

    if ($a === '' && $method === 'GET') complaints_list($pdo);
    if ($a === '' && $method === 'POST') complaints_create($pdo, $body);
    if ($a === 'team' && $method === 'GET') complaints_team($pdo);
    if ($isId) {
        $id = (int)$a;
        if ($method === 'GET' && !isset($seg[2])) complaints_one($pdo, $id, $owner);
        if ($method === 'PUT' && !isset($seg[2])) complaints_act($pdo, $id, $body, $owner);
    }
    error_response('Endpoint not found: complaints/' . $a, 404);
}

function complaints_select(): string {
    return "SELECT c.*, au.name AS author_name, CONCAT(te.first_name, ' ', te.last_name) AS target_name,
                   te.position AS target_position, co.name AS company_name
            FROM complaints c
            JOIN users au ON au.id = c.author_user_id
            LEFT JOIN employees te ON te.id = c.target_employee_id
            JOIN companies co ON co.id = c.company_id";
}

/** The caller's role on a complaint: head (author), hr, owner (sent up to them). Null = no access. */
function complaints_role(PDO $pdo, array $c, ?array $owner): ?string {
    $u = me();
    if ($c['status'] === 'escalated' || !empty($c['escalated_at'])) {
        if ($owner !== null && ($owner['ids'] === null || in_array((int)$c['company_id'], $owner['ids'], true))) return 'owner';
    }
    if ((int)$c['company_id'] === cid()) {
        if (is_hr()) return 'hr';
        if ((int)$c['author_user_id'] === (int)$u['id']) return 'head';
    }
    return null;
}

function complaints_event(PDO $pdo, int $id, string $role, string $action, ?string $note): void {
    $pdo->prepare("INSERT INTO complaint_events (complaint_id, actor_user_id, actor_name, actor_role, action, note) VALUES (?, ?, ?, ?, ?, ?)")
        ->execute([$id, (int)me()['id'], (string)(me()['name'] ?? ''), $role, $action, $note !== null && $note !== '' ? $note : null]);
}

function complaints_list(PDO $pdo): void {
    $where = ['c.company_id = ?']; $params = [cid()];
    if (!is_hr()) {
        if (!has_direct_reports($pdo)) error_response('Only team heads and HR can use complaints.', 403);
        $where[] = 'c.author_user_id = ?'; $params[] = (int)me()['id'];
    }
    if (!empty($_GET['status'])) { $where[] = 'c.status = ?'; $params[] = (string)$_GET['status']; }
    $s = $pdo->prepare(complaints_select() . ' WHERE ' . implode(' AND ', $where) . ' ORDER BY c.created_at DESC, c.id DESC LIMIT 300');
    $s->execute($params);
    json_response(['success' => true, 'data' => $s->fetchAll()]);
}

function complaints_owner_list(PDO $pdo, array $owner): void {
    $where = ["(c.status = 'escalated' OR c.escalated_at IS NOT NULL)"]; $params = [];
    if ($owner['ids'] !== null) {
        if (!$owner['ids']) json_response(['success' => true, 'data' => []]);
        $where[] = 'c.company_id IN (' . implode(',', array_map('intval', $owner['ids'])) . ')';
    }
    if (!empty($_GET['status'])) { $where[] = 'c.status = ?'; $params[] = (string)$_GET['status']; }
    $s = $pdo->prepare(complaints_select() . ' WHERE ' . implode(' AND ', $where) . ' ORDER BY c.escalated_at DESC, c.id DESC LIMIT 300');
    $s->execute($params);
    json_response(['success' => true, 'data' => $s->fetchAll()]);
}

function complaints_team(PDO $pdo): void {
    if (own_employee_id() <= 0 || !has_direct_reports($pdo)) error_response('You have no team yet.', 403);
    $s = $pdo->prepare(
        "SELECT e.id, CONCAT(e.first_name, ' ', e.last_name) AS name, e.position, e.avatar, e.email,
                (SELECT COUNT(*) FROM complaints c WHERE c.company_id = e.company_id AND c.target_employee_id = e.id AND c.author_user_id = ? AND c.status NOT IN ('resolved','dismissed')) AS open_complaints
         FROM employees e WHERE e.company_id = ? AND e.manager_id = ? AND e.status != 'inactive' ORDER BY e.first_name"
    );
    $s->execute([(int)me()['id'], cid(), own_employee_id()]);
    json_response(['success' => true, 'data' => $s->fetchAll()]);
}

function complaints_create(PDO $pdo, array $b): void {
    if (own_employee_id() <= 0 || !has_direct_reports($pdo)) error_response('Only team heads can file a complaint.', 403);
    $kind = (string)($b['kind'] ?? 'member');
    if (!in_array($kind, ['member', 'hr'], true)) error_response('Invalid complaint type', 422);
    $subject = trim((string)($b['subject'] ?? ''));
    $text = trim((string)($b['body'] ?? ''));
    if ($subject === '' || mb_strlen($subject) > 160) error_response('Write a short subject (up to 160 characters).', 422);
    if (mb_strlen($text) < 10) error_response('Describe what happened (at least 10 characters).', 422);
    if (mb_strlen($text) > 5000) error_response('The text is too long (5000 characters at most).', 422);
    $sev = (string)($b['severity'] ?? 'normal');
    if (!in_array($sev, COMPLAINT_SEVERITY, true)) $sev = 'normal';
    $target = null;
    if ($kind === 'member') {
        $target = (int)($b['target_employee_id'] ?? 0);
        if ($target <= 0 || !is_manager_of($pdo, $target)) error_response('Choose a person from your own team.', 422);
    }
    $pdo->prepare("INSERT INTO complaints (company_id, author_user_id, author_employee_id, kind, target_employee_id, subject, body, severity) VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
        ->execute([cid(), (int)me()['id'], own_employee_id(), $kind, $target, $subject, $text, $sev]);
    $id = (int)$pdo->lastInsertId();
    complaints_event($pdo, $id, 'head', 'filed', null);
    audit($pdo, 'filed', 'complaint', $id, ['kind' => $kind, 'target' => $target]);
    notify_hr($pdo, 'complaint', 'New complaint', ((string)(me()['name'] ?? '')) . ': ' . $subject, ['complaint_id' => $id], (int)me()['id']);
    $s = $pdo->prepare(complaints_select() . ' WHERE c.id = ?'); $s->execute([$id]);
    json_response(['success' => true, 'data' => $s->fetch()], 201);
}

function complaints_load(PDO $pdo, int $id): ?array {
    $s = $pdo->prepare(complaints_select() . ' WHERE c.id = ?');
    $s->execute([$id]);
    return $s->fetch() ?: null;
}

function complaints_one(PDO $pdo, int $id, ?array $owner): void {
    $c = complaints_load($pdo, $id);
    $role = $c ? complaints_role($pdo, $c, $owner) : null;
    if (!$c || !$role) error_response('Complaint not found', 404);        // 404 on purpose: nobody learns that it exists
    $e = $pdo->prepare("SELECT id, actor_name, actor_role, action, note, created_at FROM complaint_events WHERE complaint_id = ? ORDER BY id");
    $e->execute([$id]);
    $closed = in_array($c['status'], ['resolved', 'dismissed'], true);
    $c['events'] = $e->fetchAll();
    $c['my_role'] = $role;
    $c['can_comment'] = !$closed || $role !== 'head';
    $c['can_respond'] = $role === 'hr' || $role === 'owner';
    $c['can_escalate'] = $role === 'hr' && !$closed && empty($c['escalated_at']);
    json_response(['success' => true, 'data' => $c]);
}

/** Tell the owner side: platform owners and the Super Admin of the company's group. */
function complaints_notify_owners(PDO $pdo, array $c, string $title, string $text): void {
    $ids = [];
    try {
        foreach ($pdo->query("SELECT user_id FROM platform_owners")->fetchAll(PDO::FETCH_COLUMN) as $x) $ids[(int)$x] = true;
    } catch (Throwable $e) { /* no owners table yet */ }
    try {
        $g = $pdo->prepare("SELECT ga.user_id FROM group_admins ga JOIN companies co ON co.group_id = ga.group_id WHERE co.id = ?");
        $g->execute([(int)$c['company_id']]);
        foreach ($g->fetchAll(PDO::FETCH_COLUMN) as $x) $ids[(int)$x] = true;
    } catch (Throwable $e) { /* this edition has no company groups */ }
    foreach (array_keys($ids) as $uid) {
        if ($uid === (int)me()['id']) continue;
        $cs = $pdo->prepare("SELECT company_id FROM users WHERE id = ? AND status = 'active'");
        $cs->execute([$uid]);
        $home = (int)$cs->fetchColumn();
        if ($home > 0) notify($pdo, $home, $uid, 'complaint', $title, $text, ['complaint_id' => (int)$c['id']]);
    }
}

function complaints_act(PDO $pdo, int $id, array $b, ?array $owner): void {
    $c = complaints_load($pdo, $id);
    $role = $c ? complaints_role($pdo, $c, $owner) : null;
    if (!$c || !$role) error_response('Complaint not found', 404);
    $action = (string)($b['action'] ?? '');
    $note = trim((string)($b['note'] ?? ''));
    if (mb_strlen($note) > 3000) error_response('The note is too long.', 422);
    $closed = in_array($c['status'], ['resolved', 'dismissed'], true);
    $cid = (int)$c['company_id'];
    $subject = (string)$c['subject'];

    if ($action === 'comment') {
        if ($note === '') error_response('Write your note first.', 422);
        if ($closed && $role === 'head') error_response('This complaint is closed.', 409);
        complaints_event($pdo, $id, $role, 'comment', $note);
        if ($role === 'head') {
            notify_hr($pdo, 'complaint', 'Complaint updated', ((string)(me()['name'] ?? '')) . ': ' . $subject, ['complaint_id' => $id], (int)me()['id']);
        } else {
            notify($pdo, $cid, (int)$c['author_user_id'], 'complaint', 'Reply on your complaint', $subject, ['complaint_id' => $id]);
            if ($role === 'owner') notify_hr_of($pdo, $cid, 'Owner replied on a complaint', $subject, $id);
        }
    } elseif ($action === 'respond') {
        if ($role !== 'hr' && $role !== 'owner') error_response('Forbidden. Only HR or the owner can answer a complaint.', 403);
        $st = (string)($b['status'] ?? '');
        if (!in_array($st, ['in_review', 'resolved', 'dismissed'], true)) error_response('Invalid status', 422);
        if (in_array($st, ['resolved', 'dismissed'], true) && mb_strlen($note) < 3) error_response('Write what was done, so the head knows the outcome.', 422);
        $resolvedAt = in_array($st, ['resolved', 'dismissed'], true) ? date('Y-m-d H:i:s') : null;
        $keep = !empty($c['escalated_at']) && $st === 'in_review' ? 'escalated' : $st;     // a sent-up complaint stays visible to the owner while it is looked at
        $pdo->prepare("UPDATE complaints SET status = ?, resolved_at = ? WHERE id = ?")->execute([$keep, $resolvedAt, $id]);
        complaints_event($pdo, $id, $role, $st, $note);
        audit($pdo, $st, 'complaint', $id, []);
        notify($pdo, $cid, (int)$c['author_user_id'], 'complaint', $st === 'in_review' ? 'Your complaint is being looked at' : 'Your complaint was ' . $st, $subject . ($note !== '' ? " — $note" : ''), ['complaint_id' => $id]);
        if ($role === 'owner') notify_hr_of($pdo, $cid, 'Owner ' . $st . ' a complaint', $subject, $id);
        if ($role === 'hr' && !empty($c['escalated_at'])) complaints_notify_owners($pdo, $c, 'Complaint ' . $st, $subject);
    } elseif ($action === 'escalate') {
        if ($role !== 'hr') error_response('Forbidden. Only HR can send a complaint to the owner.', 403);
        if ($closed) error_response('This complaint is closed.', 409);
        if (!empty($c['escalated_at'])) error_response('It was already sent to the owner.', 409);
        if (mb_strlen($note) < 3) error_response('Write why the owner should see this.', 422);
        $pdo->prepare("UPDATE complaints SET status = 'escalated', escalated_at = NOW() WHERE id = ?")->execute([$id]);
        complaints_event($pdo, $id, 'hr', 'escalated', $note);
        audit($pdo, 'escalated', 'complaint', $id, []);
        notify($pdo, $cid, (int)$c['author_user_id'], 'complaint', 'Your complaint was sent to the owner', $subject, ['complaint_id' => $id]);
        complaints_notify_owners($pdo, $c, 'A complaint needs the owner', ($c['company_name'] ?? '') . ': ' . $subject);
    } else {
        error_response('Unknown action', 422);
    }
    complaints_one($pdo, $id, $owner);
}

/** HR of a given company (the owner acts from outside it). */
function notify_hr_of(PDO $pdo, int $companyId, string $title, string $text, int $complaintId): void {
    $s = $pdo->prepare("SELECT id FROM users WHERE company_id = ? AND role IN ('hr_admin','hr_manager') AND status = 'active'");
    $s->execute([$companyId]);
    foreach ($s->fetchAll(PDO::FETCH_COLUMN) as $uid) {
        if ((int)$uid === (int)me()['id']) continue;
        notify($pdo, $companyId, (int)$uid, 'complaint', $title, $text, ['complaint_id' => $complaintId]);
    }
}
