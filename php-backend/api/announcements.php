<?php
/**
 * Announcements API handler (company-scoped)
 */
function handle_announcements(string $path, string $method, array $body): void {
    $pdo      = getDB();
    $segments = explode('/', $path);
    $sub      = $segments[1] ?? '';
    $id       = ($sub !== '' && is_numeric($sub)) ? intval($sub) : null;

    if ($id !== null) {
        switch ($method) {
            case 'GET':    announcements_get_one($id, $pdo); break;
            case 'PUT':    require_hr(); announcements_update($id, $body, $pdo); break;
            case 'DELETE': require_hr(); announcements_delete($id, $pdo); break;
            default:       error_response('Method not allowed', 405);
        }
    } else {
        switch ($method) {
            case 'GET':  announcements_list($pdo); break;
            case 'POST': require_hr(); announcements_create($body, me(), $pdo); break;
            default:     error_response('Method not allowed', 405);
        }
    }
}

function announcements_list(PDO $pdo): void {
    $where  = ['company_id = ?'];
    $params = [cid()];

    if (!empty($_GET['priority'])) {
        $where[]  = 'priority = ?';
        $params[] = $_GET['priority'];
    }

    $limit = isset($_GET['limit']) ? intval($_GET['limit']) : 50;
    $limit = max(1, min(200, $limit));

    $stmt = $pdo->prepare("SELECT * FROM announcements WHERE " . implode(' AND ', $where) . " ORDER BY created_at DESC LIMIT " . $limit);
    $stmt->execute($params);
    json_response(['success' => true, 'data' => $stmt->fetchAll()]);
}

function announcements_get_one(int $id, PDO $pdo): void {
    $stmt = $pdo->prepare("SELECT * FROM announcements WHERE id = ? AND company_id = ?");
    $stmt->execute([$id, cid()]);
    $ann = $stmt->fetch();

    if (!$ann) {
        error_response('Announcement not found', 404);
    }
    json_response(['success' => true, 'data' => $ann]);
}

function announcements_create(array $body, array $currentUser, PDO $pdo): void {
    $title = trim($body['title'] ?? '');
    if ($title === '') {
        error_response('Title is required');
    }
    $priority = in_array($body['priority'] ?? 'medium', ['low', 'medium', 'high'], true) ? ($body['priority'] ?? 'medium') : 'medium';

    $stmt = $pdo->prepare(
        "INSERT INTO announcements (company_id, title, content, author_id, author_name, priority, created_at)
         VALUES (?, ?, ?, ?, ?, ?, NOW())"
    );
    $stmt->execute([cid(), $title, $body['content'] ?? null, $currentUser['id'], $currentUser['name'], $priority]);

    $newId = (int)$pdo->lastInsertId();
    notify_company($pdo, 'announcement', $title, mb_substr((string)($body['content'] ?? ''), 0, 140), ['announcement_id' => $newId], (int)$currentUser['id']);
    announcements_get_one($newId, $pdo);
}

function announcements_update(int $id, array $body, PDO $pdo): void {
    if (!in_company($pdo, 'announcements', $id)) {
        error_response('Announcement not found', 404);
    }

    $fields = [];
    $params = [];
    foreach (['title', 'content', 'priority'] as $field) {
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
    $pdo->prepare("UPDATE announcements SET " . implode(', ', $fields) . " WHERE id = ? AND company_id = ?")->execute($params);
    announcements_get_one($id, $pdo);
}

function announcements_delete(int $id, PDO $pdo): void {
    if (!in_company($pdo, 'announcements', $id)) {
        error_response('Announcement not found', 404);
    }
    $pdo->prepare("DELETE FROM announcements WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
    json_response(['success' => true, 'message' => 'Announcement deleted']);
}
