<?php
/**
 * Owner control panel API: who may use which premium feature.
 *
 *   GET  /owner/me                        {isOwner, isSuperAdmin}   (any signed-in user; tells the app whether to show the screen)
 *   GET  /owner/features                  the catalogue + every company in scope with its switches
 *   PUT  /owner/companies/:id/features    {flags: {key: bool, ...}}  set the switches of one company
 *   POST /owner/features/apply            {key, enabled, companyIds?}  one switch for many companies (default: all in scope)
 *   GET  /owner/audit                     who switched what, newest first
 *
 * Allowed: platform owners (every company) and group Super Admins (the companies of their own group). Nobody else, and
 * the API cannot create owners: that is done by the server-side setup script only.
 */
function handle_owner(string $path, string $method, array $body): void {
    $pdo = getDB();
    $seg = explode('/', $path);
    $sub = $seg[1] ?? '';

    $scope = owner_scope($pdo);

    if ($sub === 'me') {
        if ($method !== 'GET') error_response('Method not allowed', 405);
        json_response(['success' => true, 'data' => [
            'is_owner' => $scope !== null && $scope['mode'] === 'owner',
            'is_super_admin' => $scope !== null && $scope['mode'] === 'super',
            'can_manage' => $scope !== null,
        ]]);
    }

    // Everything else is closed to everybody else and does not even confirm that the panel exists.
    if ($scope === null) error_response('Endpoint not found: owner', 404);

    if ($sub === 'features' && ($seg[2] ?? '') === 'apply') {
        if ($method !== 'POST') error_response('Method not allowed', 405);
        owner_apply($pdo, $scope, $body);
    }
    if ($sub === 'features' || $sub === '') {
        if ($method !== 'GET') error_response('Method not allowed', 405);
        owner_overview($pdo, $scope);
    }
    if ($sub === 'companies' && ctype_digit((string)($seg[2] ?? '')) && ($seg[3] ?? '') === 'features') {
        if ($method !== 'PUT') error_response('Method not allowed', 405);
        owner_set_company($pdo, $scope, (int)$seg[2], $body);
    }
    if ($sub === 'audit') {
        if ($method !== 'GET') error_response('Method not allowed', 405);
        owner_audit($pdo, $scope);
    }
    error_response('Endpoint not found: owner/' . $sub, 404);
}

function owner_companies(PDO $pdo, array $scope): array {
    if ($scope['ids'] === null) {
        $rows = $pdo->query("SELECT id, name, slug, status FROM companies ORDER BY name")->fetchAll();
    } elseif (!$scope['ids']) {
        $rows = [];
    } else {
        $in = implode(',', array_map('intval', $scope['ids']));
        $rows = $pdo->query("SELECT id, name, slug, status FROM companies WHERE id IN ($in) ORDER BY name")->fetchAll();
    }
    return $rows;
}

function owner_in_scope(array $scope, int $companyId): bool {
    return $scope['ids'] === null || in_array($companyId, $scope['ids'], true);
}

function owner_overview(PDO $pdo, array $scope): void {
    $features = [];
    foreach (feature_registry() as $key => $f) {
        $features[] = ['key' => $key, 'title_en' => $f['title_en'], 'title_ar' => $f['title_ar'], 'desc_en' => $f['desc_en'], 'desc_ar' => $f['desc_ar']];
    }
    $companies = [];
    foreach (owner_companies($pdo, $scope) as $c) {
        $n = $pdo->prepare("SELECT COUNT(*) FROM employees WHERE company_id = ? AND status != 'inactive'");
        $n->execute([(int)$c['id']]);
        $companies[] = ['id' => (int)$c['id'], 'name' => $c['name'], 'slug' => $c['slug'], 'status' => $c['status'],
                        'employee_count' => (int)$n->fetchColumn(), 'flags' => feature_flags($pdo, (int)$c['id'])];
    }
    json_response(['success' => true, 'data' => ['mode' => $scope['mode'], 'features' => $features, 'companies' => $companies]]);
}

/** Write switches for one company; returns the changes made. Records every real change in the audit log. */
function owner_write_flags(PDO $pdo, int $companyId, array $flags): array {
    $known = feature_registry();
    $current = feature_flags($pdo, $companyId);
    $changed = [];
    foreach ($flags as $key => $val) {
        if (!isset($known[$key])) error_response("Unknown feature: $key", 422);
        $on = filter_var($val, FILTER_VALIDATE_BOOLEAN) ? 1 : 0;
        if ($current[$key] === (bool)$on && array_key_exists($key, feature_flags_raw($pdo, $companyId))) continue;
        $pdo->prepare(
            "INSERT INTO company_features (company_id, feature_key, enabled, updated_by) VALUES (?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE enabled = VALUES(enabled), updated_by = VALUES(updated_by), updated_at = NOW()"
        )->execute([$companyId, $key, $on, (int)me()['id']]);
        if ($current[$key] !== (bool)$on) {
            $pdo->prepare("INSERT INTO feature_audit (company_id, feature_key, enabled, actor_user_id) VALUES (?, ?, ?, ?)")
                ->execute([$companyId, $key, $on, (int)me()['id']]);
            $changed[] = ['key' => $key, 'enabled' => (bool)$on];
        }
    }
    return $changed;
}

function owner_set_company(PDO $pdo, array $scope, int $companyId, array $body): void {
    if (!owner_in_scope($scope, $companyId)) error_response('Forbidden. This company is outside your control.', 403);
    if (!company_get($pdo, $companyId)) error_response('Company not found', 404);
    $flags = $body['flags'] ?? null;
    if (!is_array($flags) || !$flags) error_response('flags is required', 422);
    $changed = owner_write_flags($pdo, $companyId, $flags);
    json_response(['success' => true, 'data' => ['company_id' => $companyId, 'changed' => $changed, 'flags' => feature_flags($pdo, $companyId)]]);
}

function owner_apply(PDO $pdo, array $scope, array $body): void {
    $key = (string)($body['key'] ?? '');
    if (!isset(feature_registry()[$key])) error_response('Unknown feature', 422);
    if (!array_key_exists('enabled', $body)) error_response('enabled is required', 422);
    $ids = isset($body['company_ids']) && is_array($body['company_ids'])
        ? array_map('intval', $body['company_ids'])
        : array_map(fn($c) => (int)$c['id'], owner_companies($pdo, $scope));
    $done = 0;
    foreach ($ids as $id) {
        if (!owner_in_scope($scope, $id) || !company_get($pdo, $id)) continue;
        owner_write_flags($pdo, $id, [$key => $body['enabled']]);
        $done++;
    }
    json_response(['success' => true, 'data' => ['companies' => $done, 'key' => $key, 'enabled' => (bool)filter_var($body['enabled'], FILTER_VALIDATE_BOOLEAN)]]);
}

function owner_audit(PDO $pdo, array $scope): void {
    $limit = max(1, min(200, (int)($_GET['limit'] ?? 50)));
    $where = '';
    if ($scope['ids'] !== null) $where = $scope['ids'] ? 'WHERE a.company_id IN (' . implode(',', array_map('intval', $scope['ids'])) . ')' : 'WHERE 1=0';
    $rows = $pdo->query(
        "SELECT a.id, a.company_id, c.name AS company_name, a.feature_key, a.enabled, a.actor_user_id, u.name AS actor_name, a.created_at
         FROM feature_audit a LEFT JOIN companies c ON c.id = a.company_id LEFT JOIN users u ON u.id = a.actor_user_id
         $where ORDER BY a.id DESC LIMIT $limit"
    )->fetchAll();
    json_response(['success' => true, 'data' => $rows]);
}
