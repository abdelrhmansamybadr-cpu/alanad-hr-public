<?php
/**
 * Online meetings (audio / video call between the invited people of ONE company).
 *
 *   GET    /meetings/bootstrap            can I schedule? who can I invite?
 *   GET    /meetings/ring                 meetings that are ringing for me right now (due, I am invited, not in the call, not dismissed)
 *   POST   /meetings/:id/dismiss          stop the ringing of one meeting for me
 *   GET    /meetings                      my meetings (upcoming + last 14 days); HR admin: ?all=1 = the whole company's
 *   POST   /meetings                      {title, user_ids[], scheduled_at | start_now, duration_min?, notes?}
 *   GET    /meetings/:id                  one meeting
 *   PUT    /meetings/:id                  {title?, notes?, scheduled_at?, duration_min?}   host / HR admin
 *   DELETE /meetings/:id                  cancel                                           host / HR admin
 *   POST   /meetings/:id/join             enter the call -> {present[], last_signal_id}
 *   POST   /meetings/:id/leave
 *   POST   /meetings/:id/end              end for everybody                                host / HR admin
 *   DELETE /meetings/:id/members/:userId  remove one person from the call                 host / HR admin
 *   POST   /meetings/:id/signal           {to, type, payload}  one call set-up message (offer / answer / ice / ...)
 *   GET    /meetings/:id/poll?after=N     messages addressed to me since N + who is in the call + meeting status
 *
 * The server only relays the small set-up messages (stored in meeting_signals, read by polling every 2 seconds).
 * Audio and video go directly between the devices (WebRTC), so the server carries no media. Everything is scoped to the
 * caller's company (cid()): meetings, invitations and messages of one company are never visible to another one.
 */

const MEETING_JOIN_BEFORE_MIN = 5;     // may enter this long before the start
const MEETING_GRACE_MIN = 30;          // ...and this long after the planned end
const MEETING_SIGNAL_PER_MIN = 600;

function handle_meetings(string $path, string $method, array $body): void {
    $pdo = getDB();
    $seg = explode('/', $path);
    $sub = $seg[1] ?? '';

    if ($sub === 'bootstrap' && $method === 'GET') meetings_bootstrap($pdo);
    if ($sub === 'ring' && $method === 'GET') meetings_ring($pdo);
    if ($sub === '') {
        if ($method === 'GET')  meetings_list($pdo);
        if ($method === 'POST') meetings_create($body, $pdo);
        error_response('Method not allowed', 405);
    }
    if (!ctype_digit($sub)) error_response('Not found', 404);

    $id = (int)$sub;
    $action = $seg[2] ?? '';
    $m = meetings_find($pdo, $id);

    switch ($action) {
        case '':
            if ($method === 'GET') { meetings_assert_member($pdo, $m, true); json_response(['success' => true, 'data' => meetings_json($pdo, $m)]); }
            if ($method === 'PUT' || $method === 'PATCH') meetings_update($m, $body, $pdo);
            if ($method === 'DELETE') meetings_cancel($m, $pdo);
            break;
        case 'join':    if ($method === 'POST') meetings_join($m, $pdo); break;
        case 'dismiss': if ($method === 'POST') meetings_dismiss($m, $pdo); break;
        case 'leave':   if ($method === 'POST') meetings_leave($m, $pdo); break;
        case 'end':     if ($method === 'POST') meetings_end($m, $pdo); break;
        case 'members': if ($method === 'DELETE' && isset($seg[3]) && ctype_digit($seg[3])) meetings_remove($m, (int)$seg[3], $pdo); break;
        case 'signal':  if ($method === 'POST') meetings_signal($m, $body, $pdo); break;
        case 'poll':    if ($method === 'GET') meetings_poll($m, $pdo); break;
        default: error_response('Not found', 404);
    }
    error_response('Method not allowed', 405);
}

// ------------------------------------------------------------------ helpers

function meetings_find(PDO $pdo, int $id): array {
    $s = $pdo->prepare("SELECT * FROM meetings WHERE id = ? AND company_id = ? LIMIT 1");
    $s->execute([$id, cid()]);
    $m = $s->fetch();
    if (!$m) error_response('Meeting not found', 404);
    return $m;
}

/** Row of the caller in the meeting (removed ones included) or null. */
function meetings_my_row(PDO $pdo, int $meetingId): ?array {
    $s = $pdo->prepare("SELECT * FROM meeting_participants WHERE meeting_id = ? AND user_id = ? LIMIT 1");
    $s->execute([$meetingId, (int)me()['id']]);
    return $s->fetch() ?: null;
}

function meetings_is_participant(PDO $pdo, int $meetingId, int $userId): bool {
    $s = $pdo->prepare("SELECT 1 FROM meeting_participants WHERE meeting_id = ? AND user_id = ? AND removed = 0 LIMIT 1");
    $s->execute([$meetingId, $userId]);
    return (bool)$s->fetchColumn();
}

/** Only invited people (HR admins of the company may also look at any meeting of their company). */
function meetings_assert_member(PDO $pdo, array $m, bool $allowAdmin = false): void {
    if (meetings_is_participant($pdo, (int)$m['id'], (int)me()['id'])) return;
    if ($allowAdmin && is_admin()) return;
    error_response('You are not invited to this meeting.', 403);
}

function meetings_is_host(array $m): bool {
    return (int)$m['created_by'] === (int)me()['id'] || is_admin();
}

function meetings_can_schedule(PDO $pdo): bool {
    return is_hr() || has_direct_reports($pdo);
}

/** People the caller may invite: HR -> everybody with an account in the company; a team lead -> their own team. */
function meetings_invitable(PDO $pdo): array {
    $me = (int)me()['id'];
    if (is_hr()) {
        $s = $pdo->prepare("SELECT id, name, role FROM users WHERE company_id = ? AND status = 'active' AND id <> ? ORDER BY name");
        $s->execute([cid(), $me]);
        return $s->fetchAll();
    }
    $own = own_employee_id();
    if ($own <= 0) return [];
    $s = $pdo->prepare(
        "SELECT u.id, u.name, u.role FROM users u JOIN employees e ON e.id = u.employee_id
         WHERE u.company_id = ? AND u.status = 'active' AND e.company_id = ? AND e.manager_id = ? ORDER BY u.name"
    );
    $s->execute([cid(), cid(), $own]);
    return $s->fetchAll();
}

/** Client time (ISO 8601 with or without offset) -> 'Y-m-d H:i:s' in UTC, or null when not a date. */
function meetings_utc($v): ?string {
    if (!is_string($v) || trim($v) === '') return null;
    try {
        $d = new DateTime($v);
        $d->setTimezone(new DateTimeZone('UTC'));
        return $d->format('Y-m-d H:i:s');
    } catch (Throwable $e) {
        return null;
    }
}

function meetings_iso(?string $utc): ?string {
    return $utc ? (new DateTime($utc, new DateTimeZone('UTC')))->format('Y-m-d\TH:i:s\Z') : null;
}

function meetings_can_join(array $m): bool {
    if (!in_array($m['status'], ['scheduled', 'live'], true)) return false;
    $start = new DateTime($m['scheduled_at'], new DateTimeZone('UTC'));
    $from = (clone $start)->modify('-' . MEETING_JOIN_BEFORE_MIN . ' minutes');
    $to = (clone $start)->modify('+' . ((int)$m['duration_min'] + MEETING_GRACE_MIN) . ' minutes');
    $now = new DateTime('now', new DateTimeZone('UTC'));
    return $now >= $from && $now <= $to;
}

function meetings_json(PDO $pdo, array $m): array {
    $s = $pdo->prepare(
        "SELECT p.user_id, p.role, p.joined_at, p.left_at, p.removed, u.name
         FROM meeting_participants p JOIN users u ON u.id = p.user_id WHERE p.meeting_id = ? ORDER BY p.role = 'host' DESC, u.name"
    );
    $s->execute([(int)$m['id']]);
    $people = [];
    foreach ($s->fetchAll() as $p) {
        $people[] = ['user_id' => (int)$p['user_id'], 'name' => $p['name'], 'role' => $p['role'],
                     'joined' => $p['joined_at'] !== null && $p['left_at'] === null, 'removed' => (bool)$p['removed']];
    }
    return [
        'id' => (int)$m['id'], 'title' => $m['title'], 'notes' => $m['notes'],
        'scheduled_at' => meetings_iso($m['scheduled_at']), 'duration_min' => (int)$m['duration_min'],
        'status' => $m['status'], 'created_by' => (int)$m['created_by'],
        'participants' => $people, 'can_join' => meetings_can_join($m),
    ];
}

function meetings_present(PDO $pdo, int $meetingId): array {
    $s = $pdo->prepare("SELECT user_id FROM meeting_participants WHERE meeting_id = ? AND joined_at IS NOT NULL AND left_at IS NULL AND removed = 0");
    $s->execute([$meetingId]);
    return array_map('intval', $s->fetchAll(PDO::FETCH_COLUMN));
}

function meetings_notify(PDO $pdo, array $m, string $kind): void {
    try {
        $s = $pdo->prepare("SELECT user_id FROM meeting_participants WHERE meeting_id = ? AND removed = 0 AND user_id <> ?");
        $s->execute([(int)$m['id'], (int)me()['id']]);
        $titles = ['scheduled' => 'New meeting', 'changed' => 'Meeting changed', 'cancelled' => 'Meeting cancelled', 'now' => 'Meeting started'];
        foreach ($s->fetchAll(PDO::FETCH_COLUMN) as $uid) {
            notify($pdo, cid(), (int)$uid, 'meeting', ($titles[$kind] ?? 'Meeting') . ': ' . $m['title'],
                   'By ' . (me()['name'] ?? ''), ['meeting_id' => (int)$m['id'], 'scheduled_at' => meetings_iso($m['scheduled_at'])]);
        }
    } catch (Throwable $e) { /* a missing notification must never fail the request */ }
}

// ------------------------------------------------------------------ endpoints

function meetings_bootstrap(PDO $pdo): void {
    $can = meetings_can_schedule($pdo);
    json_response(['success' => true, 'data' => [
        'can_schedule' => $can,
        'is_admin' => is_admin(),
        'invitable' => $can ? array_map(fn($u) => ['id' => (int)$u['id'], 'name' => $u['name'], 'role' => $u['role']], meetings_invitable($pdo)) : [],
    ]]);
}

function meetings_list(PDO $pdo): void {
    $all = is_admin() && !empty($_GET['all']);
    $sql = "SELECT m.* FROM meetings m WHERE m.company_id = ? AND m.scheduled_at >= (UTC_TIMESTAMP() - INTERVAL 14 DAY)";
    $params = [cid()];
    if (!$all) {
        $sql .= " AND m.id IN (SELECT meeting_id FROM meeting_participants WHERE user_id = ? AND removed = 0)";
        $params[] = (int)me()['id'];
    }
    $s = $pdo->prepare($sql . " ORDER BY m.scheduled_at LIMIT 300");
    $s->execute($params);
    json_response(['success' => true, 'data' => array_map(fn($m) => meetings_json($pdo, $m), $s->fetchAll())]);
}

function meetings_create(array $body, PDO $pdo): void {
    if (!meetings_can_schedule($pdo)) error_response('You are not allowed to schedule meetings.', 403);
    $title = trim((string)($body['title'] ?? ''));
    if ($title === '' || mb_strlen($title) > 150) error_response('A title is required (up to 150 characters).', 422);
    $notes = isset($body['notes']) ? mb_substr(trim((string)$body['notes']), 0, 2000) : null;
    $duration = (int)($body['duration_min'] ?? 30);
    if ($duration < 5 || $duration > 480) error_response('Duration must be between 5 and 480 minutes.', 422);

    $startNow = !empty($body['start_now']);
    $when = $startNow ? gmdate('Y-m-d H:i:s') : meetings_utc($body['scheduled_at'] ?? null);
    if ($when === null) error_response('A valid date and time is required.', 422);

    $ids = $body['user_ids'] ?? null;
    if (!is_array($ids) || count($ids) < 1 || count($ids) > 60) error_response('Invite between 1 and 60 people.', 422);
    $ids = array_values(array_unique(array_map('intval', $ids)));
    $allowed = array_map(fn($u) => (int)$u['id'], meetings_invitable($pdo));
    if (array_diff($ids, $allowed)) error_response('One of the invited people is not someone you may invite.', 422);

    $pdo->beginTransaction();
    try {
        $pdo->prepare("INSERT INTO meetings (company_id, title, notes, scheduled_at, duration_min, created_by, status, created_at, updated_at) VALUES (?,?,?,?,?,?, 'scheduled', UTC_TIMESTAMP(), UTC_TIMESTAMP())")
            ->execute([cid(), $title, $notes, $when, $duration, (int)me()['id']]);
        $mid = (int)$pdo->lastInsertId();
        $ins = $pdo->prepare("INSERT INTO meeting_participants (meeting_id, user_id, role) VALUES (?,?,?)");
        $ins->execute([$mid, (int)me()['id'], 'host']);
        foreach ($ids as $uid) $ins->execute([$mid, $uid, 'member']);
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        error_log('[HR API] meeting create failed: ' . $e->getMessage());
        error_response('Could not create the meeting.', 500);
    }
    $m = meetings_find($pdo, $mid);
    meetings_notify($pdo, $m, $startNow ? 'now' : 'scheduled');
    audit($pdo, 'create_meeting', 'meeting', $mid, ['title' => $title]);
    json_response(['success' => true, 'data' => meetings_json($pdo, $m)], 201);
}

function meetings_update(array $m, array $body, PDO $pdo): void {
    if (!meetings_is_host($m)) error_response('Only the host can change the meeting.', 403);
    if (in_array($m['status'], ['ended', 'cancelled'], true)) error_response('This meeting is over.', 422);
    $sets = []; $vals = [];
    if (isset($body['title'])) {
        $t = trim((string)$body['title']);
        if ($t === '' || mb_strlen($t) > 150) error_response('A title is required (up to 150 characters).', 422);
        $sets[] = 'title = ?'; $vals[] = $t;
    }
    if (array_key_exists('notes', $body)) { $sets[] = 'notes = ?'; $vals[] = $body['notes'] === null ? null : mb_substr(trim((string)$body['notes']), 0, 2000); }
    if (isset($body['scheduled_at'])) {
        $w = meetings_utc($body['scheduled_at']);
        if ($w === null) error_response('A valid date and time is required.', 422);
        $sets[] = 'scheduled_at = ?'; $vals[] = $w;
    }
    if (isset($body['duration_min'])) {
        $d = (int)$body['duration_min'];
        if ($d < 5 || $d > 480) error_response('Duration must be between 5 and 480 minutes.', 422);
        $sets[] = 'duration_min = ?'; $vals[] = $d;
    }
    if (!$sets) error_response('No fields to update');
    $vals[] = (int)$m['id'];
    $pdo->prepare("UPDATE meetings SET " . implode(', ', $sets) . ", updated_at = UTC_TIMESTAMP() WHERE id = ?")->execute($vals);
    $fresh = meetings_find($pdo, (int)$m['id']);
    if (isset($body['title']) || isset($body['scheduled_at'])) meetings_notify($pdo, $fresh, 'changed');
    json_response(['success' => true, 'data' => meetings_json($pdo, $fresh)]);
}

function meetings_cancel(array $m, PDO $pdo): void {
    if (!meetings_is_host($m)) error_response('Only the host can cancel the meeting.', 403);
    $pdo->prepare("UPDATE meetings SET status = 'cancelled', updated_at = UTC_TIMESTAMP() WHERE id = ?")->execute([(int)$m['id']]);
    meetings_notify($pdo, meetings_find($pdo, (int)$m['id']), 'cancelled');
    audit($pdo, 'cancel_meeting', 'meeting', (int)$m['id']);
    json_response(['success' => true, 'data' => ['cancelled' => true]]);
}

function meetings_join(array $m, PDO $pdo): void {
    meetings_assert_member($pdo, $m);
    if (!meetings_can_join($m)) error_response('This meeting has not started yet, or it is over.', 422);
    $me = (int)me()['id'];
    // Cursor first: anything sent to me AFTER this moment belongs to this visit, anything before is old.
    $c = $pdo->prepare("SELECT COALESCE(MAX(id), 0) FROM meeting_signals WHERE meeting_id = ? AND to_user = ?");
    $c->execute([(int)$m['id'], $me]);
    $cursor = (int)$c->fetchColumn();
    $pdo->prepare("UPDATE meeting_participants SET joined_at = UTC_TIMESTAMP(), left_at = NULL WHERE meeting_id = ? AND user_id = ?")->execute([(int)$m['id'], $me]);
    if ($m['status'] === 'scheduled') {
        $pdo->prepare("UPDATE meetings SET status = 'live', started_at = UTC_TIMESTAMP(), updated_at = UTC_TIMESTAMP() WHERE id = ?")->execute([(int)$m['id']]);
    }
    $present = array_values(array_filter(meetings_present($pdo, (int)$m['id']), fn($u) => $u !== $me));
    json_response(['success' => true, 'data' => ['present' => $present, 'last_signal_id' => $cursor]]);
}

function meetings_leave(array $m, PDO $pdo): void {
    $row = meetings_my_row($pdo, (int)$m['id']);
    if (!$row) error_response('You are not invited to this meeting.', 403);
    $pdo->prepare("UPDATE meeting_participants SET left_at = UTC_TIMESTAMP() WHERE meeting_id = ? AND user_id = ?")->execute([(int)$m['id'], (int)me()['id']]);
    if ($m['status'] === 'live' && !meetings_present($pdo, (int)$m['id'])) {
        $pdo->prepare("UPDATE meetings SET status = 'ended', ended_at = UTC_TIMESTAMP(), updated_at = UTC_TIMESTAMP() WHERE id = ?")->execute([(int)$m['id']]);
    }
    json_response(['success' => true, 'data' => ['left' => true]]);
}

function meetings_end(array $m, PDO $pdo): void {
    if (!meetings_is_host($m)) error_response('Only the host can end the meeting for everybody.', 403);
    $pdo->prepare("UPDATE meetings SET status = 'ended', ended_at = UTC_TIMESTAMP(), updated_at = UTC_TIMESTAMP() WHERE id = ?")->execute([(int)$m['id']]);
    $pdo->prepare("UPDATE meeting_participants SET left_at = UTC_TIMESTAMP() WHERE meeting_id = ? AND joined_at IS NOT NULL AND left_at IS NULL")->execute([(int)$m['id']]);
    json_response(['success' => true, 'data' => ['ended' => true]]);
}

function meetings_remove(array $m, int $userId, PDO $pdo): void {
    if (!meetings_is_host($m)) error_response('Only the host can remove people.', 403);
    if ($userId === (int)$m['created_by']) error_response('The host cannot be removed.', 422);
    $u = $pdo->prepare("UPDATE meeting_participants SET removed = 1, left_at = UTC_TIMESTAMP() WHERE meeting_id = ? AND user_id = ?");
    $u->execute([(int)$m['id'], $userId]);
    if (!$u->rowCount()) error_response('This person is not in the meeting.', 404);
    json_response(['success' => true, 'data' => ['removed' => true]]);
}

function meetings_signal(array $m, array $body, PDO $pdo): void {
    $row = meetings_my_row($pdo, (int)$m['id']);
    if (!$row || (int)$row['removed'] === 1) error_response('You are not in this meeting.', 403);
    if ($row['joined_at'] === null || $row['left_at'] !== null) error_response('Join the call first.', 422);
    if (in_array($m['status'], ['ended', 'cancelled'], true)) error_response('The meeting is over.', 422);

    $to = (int)($body['to'] ?? 0);
    $type = (string)($body['type'] ?? '');
    $payload = $body['payload'] ?? null;
    if ($to <= 0 || $to === (int)me()['id'] || !meetings_is_participant($pdo, (int)$m['id'], $to)) error_response('The receiver is not in this meeting.', 422);
    if (!preg_match('/^[a-z0-9_.]{1,24}$/', $type)) error_response('Invalid message type.', 422);
    if ($payload !== null && (!is_string($payload) || strlen($payload) > 200000)) error_response('Message too large.', 422);

    $key = 'msig:' . (int)me()['id'];
    if (throttle_count($pdo, $key, 1) >= MEETING_SIGNAL_PER_MIN) error_response('Too many messages. Please slow down.', 429);
    throttle_hit($pdo, $key);

    $pdo->prepare("INSERT INTO meeting_signals (meeting_id, from_user, to_user, type, payload, created_at) VALUES (?,?,?,?,?, UTC_TIMESTAMP())")
        ->execute([(int)$m['id'], (int)me()['id'], $to, $type, $payload]);
    json_response(['success' => true, 'data' => ['id' => (int)$pdo->lastInsertId()]]);
}

function meetings_poll(array $m, PDO $pdo): void {
    $row = meetings_my_row($pdo, (int)$m['id']);
    if (!$row) error_response('You are not invited to this meeting.', 403);
    $after = max(0, (int)($_GET['after'] ?? 0));
    $s = $pdo->prepare("SELECT id, from_user, type, payload FROM meeting_signals WHERE meeting_id = ? AND to_user = ? AND id > ? ORDER BY id LIMIT 200");
    $s->execute([(int)$m['id'], (int)me()['id'], $after]);
    $signals = array_map(fn($r) => ['id' => (int)$r['id'], 'from' => (int)$r['from_user'], 'type' => $r['type'], 'payload' => $r['payload']], $s->fetchAll());
    if (mt_rand(1, 60) === 1) $pdo->exec("DELETE FROM meeting_signals WHERE created_at < (UTC_TIMESTAMP() - INTERVAL 1 DAY)");
    json_response(['success' => true, 'data' => [
        'status' => $m['status'],
        'removed' => (int)$row['removed'] === 1,
        'signals' => $signals,
        'present' => meetings_present($pdo, (int)$m['id']),
    ]]);
}

/** Meetings ringing for the caller: due now (or already running), invited, not the host, not yet in the call, not dismissed. */
function meetings_ring(PDO $pdo): void {
    $me = (int)me()['id'];
    $s = $pdo->prepare(
        "SELECT m.id, m.title, m.scheduled_at, m.status, u.name AS host_name
         FROM meetings m
         JOIN meeting_participants p ON p.meeting_id = m.id AND p.user_id = ? AND p.removed = 0
         JOIN users u ON u.id = m.created_by
         WHERE m.company_id = ? AND m.status IN ('scheduled','live') AND m.created_by <> ?
           AND p.joined_at IS NULL AND p.dismissed_at IS NULL
           AND m.scheduled_at <= (UTC_TIMESTAMP() + INTERVAL 1 MINUTE)
           AND DATE_ADD(m.scheduled_at, INTERVAL m.duration_min MINUTE) >= UTC_TIMESTAMP()
         ORDER BY m.scheduled_at LIMIT 5"
    );
    $s->execute([$me, cid(), $me]);
    $out = array_map(fn($r) => ['id' => (int)$r['id'], 'title' => $r['title'], 'host_name' => $r['host_name'], 'scheduled_at' => meetings_iso($r['scheduled_at']), 'status' => $r['status']], $s->fetchAll());
    json_response(['success' => true, 'data' => $out]);
}

function meetings_dismiss(array $m, PDO $pdo): void {
    $row = meetings_my_row($pdo, (int)$m['id']);
    if (!$row) error_response('You are not invited to this meeting.', 403);
    $pdo->prepare("UPDATE meeting_participants SET dismissed_at = UTC_TIMESTAMP() WHERE meeting_id = ? AND user_id = ?")->execute([(int)$m['id'], (int)me()['id']]);
    json_response(['success' => true, 'data' => ['dismissed' => true]]);
}
