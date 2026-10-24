<?php
/**
 * Peer kudos: colleagues praise each other in a company-wide feed (company-scoped)
 *
 *   GET    /kudos?limit=50          the feed, newest first (everyone)
 *   GET    /kudos/me                kudos I received + counts per badge
 *   GET    /kudos/top               who was praised most in the last 30 days
 *   POST   /kudos                   {to_employee_id, badge, message}   max 5 a day, never to yourself
 *   DELETE /kudos/{id}              the author or HR
 */
const KUDOS_BADGES = ['thanks', 'great_job', 'teamwork', 'creative', 'helpful', 'leader'];

function handle_kudos(string $path, string $method, array $body): void {
    $pdo = getDB();
    $seg = explode('/', $path);
    $sub = $seg[1] ?? '';

    if ($method === 'GET' && $sub === '')    kudos_feed($pdo);
    if ($method === 'GET' && $sub === 'me')  kudos_mine($pdo);
    if ($method === 'GET' && $sub === 'top') kudos_top($pdo);
    if ($method === 'POST' && $sub === '')   kudos_send($body, $pdo);
    if ($method === 'DELETE' && ctype_digit($sub)) kudos_delete((int)$sub, $pdo);
    error_response('Not found', 404);
}

const KUDOS_SELECT =
    "SELECT k.id, k.badge, k.message, k.created_at, k.from_employee_id, k.to_employee_id,
            CONCAT(f.first_name, ' ', f.last_name) AS from_name, f.avatar AS from_avatar,
            CONCAT(t.first_name, ' ', t.last_name) AS to_name,   t.avatar AS to_avatar
     FROM kudos k
     JOIN employees f ON f.id = k.from_employee_id
     JOIN employees t ON t.id = k.to_employee_id";

function kudos_feed(PDO $pdo): void {
    $limit = isset($_GET['limit']) ? max(1, min(100, intval($_GET['limit']))) : 50;
    $s = $pdo->prepare(KUDOS_SELECT . " WHERE k.company_id = ? ORDER BY k.id DESC LIMIT $limit");
    $s->execute([cid()]);
    json_response(['success' => true, 'data' => $s->fetchAll()]);
}

function kudos_mine(PDO $pdo): void {
    $eid = own_employee_id();
    if ($eid <= 0) error_response('No employee record linked to this account', 404);
    $s = $pdo->prepare(KUDOS_SELECT . " WHERE k.company_id = ? AND k.to_employee_id = ? ORDER BY k.id DESC LIMIT 100");
    $s->execute([cid(), $eid]);
    $items = $s->fetchAll();
    $counts = [];
    foreach ($items as $i) $counts[$i['badge']] = ($counts[$i['badge']] ?? 0) + 1;
    json_response(['success' => true, 'data' => ['total' => count($items), 'by_badge' => (object)$counts, 'items' => $items]]);
}

function kudos_top(PDO $pdo): void {
    $s = $pdo->prepare(
        "SELECT t.id AS employee_id, CONCAT(t.first_name, ' ', t.last_name) AS name, t.avatar, COUNT(*) AS kudos
         FROM kudos k JOIN employees t ON t.id = k.to_employee_id
         WHERE k.company_id = ? AND k.created_at >= (NOW() - INTERVAL 30 DAY) AND t.status != 'inactive'
         GROUP BY t.id ORDER BY kudos DESC, name LIMIT 5"
    );
    $s->execute([cid()]);
    json_response(['success' => true, 'data' => $s->fetchAll()]);
}

function kudos_send(array $body, PDO $pdo): void {
    $from = own_employee_id();
    if ($from <= 0) error_response('No employee record linked to this account', 403);
    $to = (int)($body['to_employee_id'] ?? 0);
    $msg = trim((string)($body['message'] ?? ''));
    $badge = (string)($body['badge'] ?? 'thanks');
    if (!in_array($badge, KUDOS_BADGES, true)) $badge = 'thanks';
    if ($to <= 0 || !employee_in_company($pdo, $to)) error_response('Choose a colleague', 422);
    if ($to === $from) error_response('You cannot send kudos to yourself', 422);
    if ($msg === '' || mb_strlen($msg) > 500) error_response('Write a short message (up to 500 characters)', 422);

    $n = $pdo->prepare("SELECT COUNT(*) FROM kudos WHERE company_id = ? AND from_employee_id = ? AND created_at >= (NOW() - INTERVAL 1 DAY)");
    $n->execute([cid(), $from]);
    if ((int)$n->fetchColumn() >= 5) error_response('You can send up to 5 kudos a day. Try again tomorrow.', 429);

    $pdo->prepare("INSERT INTO kudos (company_id, from_employee_id, to_employee_id, badge, message) VALUES (?,?,?,?,?)")
        ->execute([cid(), $from, $to, $badge, $msg]);
    $id = (int)$pdo->lastInsertId();

    $who = $pdo->prepare("SELECT CONCAT(first_name, ' ', last_name) FROM employees WHERE id = ?");
    $who->execute([$from]);
    notify_employee($pdo, $to, 'kudos', 'Kudos from ' . $who->fetchColumn(), mb_substr($msg, 0, 140), ['kudos_id' => $id, 'badge' => $badge]);

    kudos_maybe_reward($pdo, $to, $id);

    $s = $pdo->prepare(KUDOS_SELECT . " WHERE k.id = ?");
    $s->execute([$id]);
    json_response(['success' => true, 'data' => $s->fetch()], 201);
}

function kudos_delete(int $id, PDO $pdo): void {
    $s = $pdo->prepare("SELECT from_employee_id FROM kudos WHERE id = ? AND company_id = ?");
    $s->execute([$id, cid()]);
    $from = $s->fetchColumn();
    if ($from === false) error_response('Not found', 404);
    if (!is_hr() && (int)$from !== own_employee_id()) error_response('Forbidden. Insufficient permissions.', 403);
    $pdo->prepare("DELETE FROM kudos WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
    json_response(['success' => true, 'message' => 'Deleted']);
}


/** Every Nth kudos an employee has received earns one green point (the number is a points setting; 0 = off). */
function kudos_maybe_reward(PDO $pdo, int $employeeId, int $kudosId): void {
    require_once __DIR__ . '/../helpers/points.php';
    $cfg = points_config($pdo);
    $every = (int)($cfg['kudos_green_every'] ?? 0);
    if (empty($cfg['enabled']) || $every <= 0) return;
    $n = $pdo->prepare("SELECT COUNT(*) FROM kudos WHERE company_id = ? AND to_employee_id = ?");
    $n->execute([cid(), $employeeId]);
    $count = (int)$n->fetchColumn();
    if ($count === 0 || $count % $every !== 0) return;
    // auto_key makes the reward idempotent: the same milestone is never paid twice (e.g. after a delete and a new kudos)
    $ins = $pdo->prepare("INSERT IGNORE INTO points_ledger (company_id, employee_id, date, color, reason, source, auto_key, note, created_by) VALUES (?,?,?,'green','kudos','manual',?,?,?)");
    $ins->execute([cid(), $employeeId, att_now($pdo)->format('Y-m-d'), 'k' . $count, "$count kudos from colleagues", (int)me()['id']]);
    if ($ins->rowCount() > 0) {
        notify_employee($pdo, $employeeId, 'points', 'A green point from your colleagues!', "You have received $count kudos, so you earned a green point.", ['color' => 'green', 'kudos_id' => $kudosId]);
    }
}
