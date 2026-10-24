<?php
/**
 * Leave types (company-scoped)
 *
 *   GET    /leave-types                 active types (HR also gets inactive with ?all=1)
 *   POST   /leave-types                 {code?, name, days_per_year, paid, color}   (admin)
 *   PUT    /leave-types/{id}            (admin)
 *   DELETE /leave-types/{id}            (admin) — deactivates when the type is already used
 */
function handle_leave_types(string $path, string $method, array $body): void {
    $pdo = getDB();
    $sub = explode('/', $path)[1] ?? '';
    $id  = ($sub !== '' && is_numeric($sub)) ? intval($sub) : null;

    if ($id !== null) {
        switch ($method) {
            case 'PUT':    require_admin(); leave_types_update($id, $body, $pdo); break;
            case 'DELETE': require_admin(); leave_types_delete($id, $pdo); break;
            default:       error_response('Method not allowed', 405);
        }
        return;
    }
    switch ($method) {
        case 'GET':  leave_types_list($pdo); break;
        case 'POST': require_admin(); leave_types_create($body, $pdo); break;
        default:     error_response('Method not allowed', 405);
    }
}

function leave_types_fetch(PDO $pdo, int $id): ?array {
    $s = $pdo->prepare("SELECT * FROM leave_types WHERE id = ? AND company_id = ?");
    $s->execute([$id, cid()]);
    return $s->fetch() ?: null;
}

function leave_types_list(PDO $pdo): void {
    $sql = "SELECT * FROM leave_types WHERE company_id = ?" . (is_hr() && !empty($_GET['all']) ? '' : ' AND is_active = 1') . " ORDER BY id";
    $s = $pdo->prepare($sql);
    $s->execute([cid()]);
    json_response(['success' => true, 'data' => $s->fetchAll()]);
}

function leave_types_color($v): string {
    return preg_match('/^#[0-9A-Fa-f]{6}$/', (string)$v) ? strtoupper($v) : '#00617A';
}

function leave_types_create(array $body, PDO $pdo): void {
    $name = trim((string)($body['name'] ?? ''));
    if ($name === '') error_response('Name is required', 422);
    $code = strtolower(preg_replace('/[^a-z0-9_]+/i', '_', trim((string)($body['code'] ?? $name))));
    $code = trim(substr($code, 0, 40), '_');
    if ($code === '') error_response('Invalid code', 422);

    $dup = $pdo->prepare("SELECT 1 FROM leave_types WHERE company_id = ? AND code = ?");
    $dup->execute([cid(), $code]);
    if ($dup->fetchColumn()) error_response('A leave type with this code already exists', 409);

    $pdo->prepare("INSERT INTO leave_types (company_id, code, name, days_per_year, paid, color) VALUES (?, ?, ?, ?, ?, ?)")
        ->execute([cid(), $code, mb_substr($name, 0, 100), max(0, intval($body['days_per_year'] ?? 0)), !empty($body['paid']) || !isset($body['paid']) ? 1 : 0, leave_types_color($body['color'] ?? null)]);
    json_response(['success' => true, 'data' => leave_types_fetch($pdo, (int)$pdo->lastInsertId())], 201);
}

function leave_types_update(int $id, array $body, PDO $pdo): void {
    if (!leave_types_fetch($pdo, $id)) error_response('Leave type not found', 404);
    $fields = []; $params = [];
    if (array_key_exists('name', $body))          { $fields[] = 'name = ?';          $params[] = mb_substr(trim((string)$body['name']), 0, 100); }
    if (array_key_exists('days_per_year', $body)) { $fields[] = 'days_per_year = ?'; $params[] = max(0, intval($body['days_per_year'])); }
    if (array_key_exists('paid', $body))          { $fields[] = 'paid = ?';          $params[] = $body['paid'] ? 1 : 0; }
    if (array_key_exists('color', $body))         { $fields[] = 'color = ?';         $params[] = leave_types_color($body['color']); }
    if (array_key_exists('is_active', $body))     { $fields[] = 'is_active = ?';     $params[] = $body['is_active'] ? 1 : 0; }
    if (!$fields) error_response('No fields to update');
    $params[] = $id; $params[] = cid();
    $pdo->prepare("UPDATE leave_types SET " . implode(', ', $fields) . " WHERE id = ? AND company_id = ?")->execute($params);
    json_response(['success' => true, 'data' => leave_types_fetch($pdo, $id)]);
}

function leave_types_delete(int $id, PDO $pdo): void {
    $t = leave_types_fetch($pdo, $id);
    if (!$t) error_response('Leave type not found', 404);
    $used = $pdo->prepare("SELECT 1 FROM leaves WHERE company_id = ? AND type = ? LIMIT 1");
    $used->execute([cid(), $t['code']]);
    if ($used->fetchColumn()) {
        $pdo->prepare("UPDATE leave_types SET is_active = 0 WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
        json_response(['success' => true, 'message' => 'Leave type is in use and was deactivated instead of deleted']);
    }
    $pdo->prepare("DELETE FROM leave_types WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
    json_response(['success' => true, 'message' => 'Leave type deleted']);
}
