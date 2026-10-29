<?php
/**
 * In-app notifications (always the caller's own)
 *
 *   GET    /notifications?unread=1&limit=50   list + unread_count
 *   GET    /notifications/count               {unread_count}
 *   POST   /notifications/read                {ids: [1,2]} or {all: true}
 *   DELETE /notifications/{id}
 */
function handle_notifications(string $path, string $method, array $body): void {
    $pdo = getDB();
    $sub = explode('/', $path)[1] ?? '';
    if ($method === 'GET' && ($sub === 'count' || $sub === '')) {
        require_once __DIR__ . '/../helpers/reminders.php'; reminders_run($pdo);
        require_once __DIR__ . '/../helpers/certificates.php'; exit_apply_due($pdo);           // accounts whose planned closing time has come
        if (is_hr()) { require_once __DIR__ . '/../helpers/contracts.php'; contracts_tick($pdo); }   // contract expiry alarms (once a day)
    }

    if ($sub === 'count' && $method === 'GET') {
        json_response(['success' => true, 'data' => ['unread_count' => notifications_unread($pdo)]]);
    }
    if ($sub === 'read' && $method === 'POST') {
        notifications_mark_read($body, $pdo);
    }
    if ($sub !== '' && is_numeric($sub) && $method === 'DELETE') {
        $pdo->prepare("DELETE FROM notifications WHERE id = ? AND user_id = ? AND company_id = ?")->execute([intval($sub), (int)me()['id'], cid()]);
        json_response(['success' => true, 'message' => 'Notification deleted']);
    }
    if ($sub === '' && $method === 'GET') {
        notifications_list($pdo);
    }
    error_response('Not found', 404);
}

function notifications_unread(PDO $pdo): int {
    $s = $pdo->prepare("SELECT COUNT(*) FROM notifications WHERE user_id = ? AND company_id = ? AND read_at IS NULL");
    $s->execute([(int)me()['id'], cid()]);
    return (int)$s->fetchColumn();
}

function notifications_list(PDO $pdo): void {
    $where  = ['user_id = ?', 'company_id = ?'];
    $params = [(int)me()['id'], cid()];
    if (!empty($_GET['unread'])) $where[] = 'read_at IS NULL';
    if (!empty($_GET['after'])) { $where[] = 'id > ?'; $params[] = max(0, intval($_GET['after'])); }   // used by device polling
    $limit = isset($_GET['limit']) ? max(1, min(100, intval($_GET['limit']))) : 50;

    $s = $pdo->prepare("SELECT id, type, title, body, data, read_at, created_at FROM notifications WHERE " . implode(' AND ', $where) . " ORDER BY id DESC LIMIT $limit");
    $s->execute($params);
    $rows = $s->fetchAll();
    foreach ($rows as &$r) {
        $r['data'] = $r['data'] ? json_decode($r['data'], true) : null;
    }
    unset($r);
    json_response(['success' => true, 'data' => ['unread_count' => notifications_unread($pdo), 'items' => $rows]]);
}

function notifications_mark_read(array $body, PDO $pdo): void {
    if (!empty($body['all'])) {
        $pdo->prepare("UPDATE notifications SET read_at = NOW() WHERE user_id = ? AND company_id = ? AND read_at IS NULL")->execute([(int)me()['id'], cid()]);
    } else {
        $ids = array_values(array_filter(array_map('intval', (array)($body['ids'] ?? [])), fn($i) => $i > 0));
        if ($ids) {
            $in = implode(',', array_fill(0, count($ids), '?'));
            $pdo->prepare("UPDATE notifications SET read_at = NOW() WHERE user_id = ? AND company_id = ? AND read_at IS NULL AND id IN ($in)")
                ->execute(array_merge([(int)me()['id'], cid()], $ids));
        }
    }
    json_response(['success' => true, 'data' => ['unread_count' => notifications_unread($pdo)]]);
}
