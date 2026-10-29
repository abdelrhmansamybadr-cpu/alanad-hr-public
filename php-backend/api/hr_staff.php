<?php
/**
 * HR Staff API handler (company-scoped)
 * Manages the company's HR admins and HR managers. Only admins change staff.
 */
function handle_hr_staff(string $path, string $method, array $body): void {
    $pdo      = getDB();
    $segments = explode('/', $path);
    $sub      = $segments[1] ?? '';
    $sub2     = $segments[2] ?? '';
    $id       = ($sub !== '' && is_numeric($sub)) ? intval($sub) : null;

    require_hr();

    if ($id !== null) {
        // /hr-staff/{id}/status | /password | /permissions are convenience aliases of PUT /hr-staff/{id}
        if ($sub2 !== '' && $method === 'PUT') {
            if ($sub2 === 'status')      $body = ['status' => $body['status'] ?? null];
            elseif ($sub2 === 'password') $body = ['password' => $body['password'] ?? $body['new_password'] ?? null];
            elseif ($sub2 === 'permissions') $body = ['permissions' => $body['permissions'] ?? []];
        }
        switch ($method) {
            case 'GET':    hr_staff_get_one($id, $pdo); break;
            case 'PUT':    hr_staff_update($id, $body, $pdo); break;
            case 'DELETE': hr_staff_delete($id, $pdo); break;
            default:       error_response('Method not allowed', 405);
        }
    } else {
        switch ($method) {
            case 'GET':  hr_staff_list($pdo); break;
            case 'POST': require_admin(); hr_staff_create($body, $pdo); break;
            default:     error_response('Method not allowed', 405);
        }
    }
}

/**
 * The platform owner's account (name, e-mail, phone, password, status, role, permissions) can be changed by the owner only -
 * never by an HR admin / manager. Changing the e-mail or phone would also let someone take the account over through
 * "forgot password", so every change is blocked, not just the password.
 */
function hr_staff_lock_owner(PDO $pdo, int $targetId): void {
    if (!function_exists('platform_owner_check')) require_once __DIR__ . '/../helpers/features.php';
    if ($targetId !== (int)me()['id'] && platform_owner_check($pdo, $targetId)) {
        error_response('This is the owner account. Only the owner can change it (a forgotten password is reset by e-mail or SMS).', 403);
    }
    // A group super admin works "under the owner": only the owner (or the person themself) may change or close that account.
    if ($targetId !== (int)me()['id'] && !platform_owner_check($pdo, (int)me()['id'])) {
        $g = $pdo->prepare("SELECT 1 FROM group_admins WHERE user_id = ? LIMIT 1");
        $g->execute([$targetId]);
        if ($g->fetchColumn()) error_response('This is a group super admin account. Only the owner can change or close it.', 403);
    }
}

function hr_staff_columns(): string {
    return "u.id, u.name, u.email, u.role, u.avatar, u.title, u.phone, u.status,
            u.created_at, u.created_by, u.last_login_at, creator.name AS created_by_name";
}

function hr_staff_attach_permissions(PDO $pdo, array $member): array {
    $p = $pdo->prepare("SELECT module, enabled FROM user_permissions WHERE user_id = ?");
    $p->execute([$member['id']]);
    $member['permissions'] = $p->fetchAll();
    if (!function_exists('platform_owner_check')) require_once __DIR__ . '/../helpers/features.php';
    $member['is_owner'] = platform_owner_check($pdo, (int)$member['id']);
    return $member;
}

function hr_staff_list(PDO $pdo): void {
    $where  = ["u.company_id = ?", "u.role IN ('hr_admin', 'hr_manager')"];
    $params = [cid()];
    if (!is_admin()) {                       // an HR manager only sees their own account
        $where[]  = 'u.id = ?';
        $params[] = (int)me()['id'];
    }

    $stmt = $pdo->prepare(
        "SELECT " . hr_staff_columns() . " FROM users u LEFT JOIN users creator ON creator.id = u.created_by
         WHERE " . implode(' AND ', $where) . " ORDER BY u.created_at DESC"
    );
    $stmt->execute($params);
    $staff = array_map(fn($m) => hr_staff_attach_permissions($pdo, $m), $stmt->fetchAll());
    json_response(['success' => true, 'data' => $staff]);
}

function hr_staff_fetch(int $id, PDO $pdo): ?array {
    $stmt = $pdo->prepare(
        "SELECT " . hr_staff_columns() . " FROM users u LEFT JOIN users creator ON creator.id = u.created_by
         WHERE u.id = ? AND u.company_id = ? AND u.role IN ('hr_admin', 'hr_manager')"
    );
    $stmt->execute([$id, cid()]);
    $m = $stmt->fetch();
    return $m ? hr_staff_attach_permissions($pdo, $m) : null;
}

function hr_staff_get_one(int $id, PDO $pdo): void {
    if (!is_admin() && $id !== (int)me()['id']) error_response('Forbidden. Insufficient permissions.', 403);
    $member = hr_staff_fetch($id, $pdo);
    if (!$member) {
        error_response('HR staff member not found', 404);
    }
    json_response(['success' => true, 'data' => $member]);
}

function hr_staff_save_permissions(PDO $pdo, int $userId, $permissions): void {
    if (!is_array($permissions)) return;
    $stmt = $pdo->prepare(
        "INSERT INTO user_permissions (user_id, module, enabled) VALUES (?, ?, ?)
         ON DUPLICATE KEY UPDATE enabled = VALUES(enabled)"
    );
    foreach ($permissions as $perm) {
        if (!empty($perm['module'])) {
            $stmt->execute([$userId, preg_replace('/[^a-z_]/', '', strtolower((string)$perm['module'])), !empty($perm['enabled']) ? 1 : 0]);
        }
    }
}

function hr_staff_create(array $body, PDO $pdo): void {
    $name     = trim($body['name'] ?? '');
    $email    = strtolower(trim($body['email'] ?? ''));
    $password = (string)($body['password'] ?? '');
    $role     = $body['role'] ?? 'hr_manager';

    if ($name === '' || $email === '' || $password === '') {
        error_response('name, email and password are required');
    }
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) error_response('Invalid email address', 422);
    if (strlen($password) < 8) error_response('Password must be at least 8 characters', 422);
    if (!in_array($role, ['hr_admin', 'hr_manager'], true)) error_response('Invalid role. Must be hr_admin or hr_manager', 422);

    $check = $pdo->prepare("SELECT id FROM users WHERE email = ?");
    $check->execute([$email]);
    if ($check->fetch()) error_response('A user with this email already exists', 409);

    $pdo->prepare(
        "INSERT INTO users (company_id, name, email, password_hash, role, title, phone, status, created_by, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'active', ?, NOW())"
    )->execute([cid(), $name, $email, password_hash($password, PASSWORD_BCRYPT), $role, $body['title'] ?? null, $body['phone'] ?? null, (int)me()['id']]);
    $newId = (int)$pdo->lastInsertId();

    hr_staff_save_permissions($pdo, $newId, $body['permissions'] ?? []);
    json_response(['success' => true, 'data' => hr_staff_fetch($newId, $pdo)], 201);
}

function hr_staff_update(int $id, array $body, PDO $pdo): void {
    $self = $id === (int)me()['id'];
    if (!is_admin() && !$self) error_response('Forbidden. Only admins can edit other staff.', 403);

    $target = hr_staff_fetch($id, $pdo);
    if (!$target) error_response('HR staff member not found', 404);
    hr_staff_lock_owner($pdo, $id);

    $fields = [];
    $params = [];
    foreach (['name', 'title', 'phone', 'avatar'] as $f) {
        if (array_key_exists($f, $body)) { $fields[] = "$f = ?"; $params[] = $body[$f]; }
    }
    if (is_admin()) {
        if (array_key_exists('email', $body)) {
            $email = strtolower(trim((string)$body['email']));
            if (!filter_var($email, FILTER_VALIDATE_EMAIL)) error_response('Invalid email address', 422);
            $d = $pdo->prepare("SELECT id FROM users WHERE email = ? AND id != ?");
            $d->execute([$email, $id]);
            if ($d->fetch()) error_response('A user with this email already exists', 409);
            $fields[] = 'email = ?'; $params[] = $email;
        }
        if (isset($body['status'])) {
            if (!in_array($body['status'], ['active', 'suspended', 'disabled'], true)) error_response('Invalid status', 422);
            if ($self && $body['status'] !== 'active') error_response('You cannot disable your own account', 422);
            $fields[] = 'status = ?'; $params[] = $body['status'];
        }
        if (isset($body['role'])) {
            if (!in_array($body['role'], ['hr_admin', 'hr_manager'], true)) error_response('Invalid role', 422);
            if ($self && $body['role'] !== 'hr_admin') error_response('You cannot remove your own admin role', 422);
            $fields[] = 'role = ?'; $params[] = $body['role'];
        }
    }
    if (!empty($body['password'])) {
        if (strlen((string)$body['password']) < 8) error_response('Password must be at least 8 characters', 422);
        $fields[] = 'password_hash = ?'; $params[] = password_hash((string)$body['password'], PASSWORD_BCRYPT);
    }

    if ($fields) {
        $params[] = $id;
        $params[] = cid();
        $pdo->prepare("UPDATE users SET " . implode(', ', $fields) . " WHERE id = ? AND company_id = ?")->execute($params);
        if (!empty($body['password']) || (isset($body['status']) && $body['status'] !== 'active')) {
            $pdo->prepare("DELETE FROM sessions WHERE user_id = ?")->execute([$id]);   // force re-login
        }
    }
    if (is_admin()) hr_staff_save_permissions($pdo, $id, $body['permissions'] ?? null);

    if (!$fields && !isset($body['permissions'])) error_response('No fields to update');
    json_response(['success' => true, 'data' => hr_staff_fetch($id, $pdo)]);
}

function hr_staff_delete(int $id, PDO $pdo): void {
    require_admin();
    if ($id === (int)me()['id']) error_response('You cannot delete your own account', 422);
    if (!hr_staff_fetch($id, $pdo)) error_response('HR staff member not found', 404);
    hr_staff_lock_owner($pdo, $id);

    $pdo->prepare("DELETE FROM sessions WHERE user_id = ?")->execute([$id]);
    $pdo->prepare("DELETE FROM user_permissions WHERE user_id = ?")->execute([$id]);
    $pdo->prepare("DELETE FROM users WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
    json_response(['success' => true, 'message' => 'HR staff member deleted']);
}
