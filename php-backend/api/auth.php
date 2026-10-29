<?php
/**
 * Auth API handler
 *
 *   POST /auth/login
 *   GET  /auth/me
 *   POST /auth/logout
 *   PUT  /auth/profile            own name / phone / avatar / title
 *   PUT  /auth/password           change own password
 *   POST /auth/register           (admin) add an HR user to the company
 *   /auth/webauthn/...            passkey sign-in (Windows Hello) — see api/webauthn.php
 *
 *   Employee self-service sign-in (no e-mail server needed — HR hands out codes):
 *   POST /auth/employee/check-email      -> {status: hr | not_found | needs_activation | active}
 *   POST /auth/employee/activate         {email, code, password}   first sign-in with the invite code from HR
 *   POST /auth/employee/login            {email, password}
 *   POST /auth/employee/forgot-password  -> generic answer; the employee asks HR for a reset code
 *   POST /auth/employee/reset-password   {email, code, new_password}
 *
 *   POST /companies/register      public sign-up of a new company + its first admin
 */
function handle_auth(string $path, string $method, array $body): void {
    $pdo = getDB();
    $segments = explode('/', $path);
    $action = $segments[1] ?? '';
    $sub = $segments[2] ?? '';

    // Company sign-up lives under /companies/register
    if ($segments[0] === 'companies') {
        if (($segments[1] ?? '') === 'register' && $method === 'POST') {
            if (app_lock_slug() !== null) error_response('Creating companies is not available in this app.', 403);
            auth_register_company($body, $pdo);
            return;
        }
        error_response('Not found', 404);
    }

    if ($action === 'employee') {
        handle_auth_employee($sub, $method, $body, $pdo);
        return;
    }

    switch ($action) {
        case 'login':
            if ($method !== 'POST') error_response('Method not allowed', 405);
            auth_login($body, $pdo);
            break;

        case 'register':
            if ($method !== 'POST') error_response('Method not allowed', 405);
            hr_set_user(require_auth());
            require_admin();
            auth_register($body, $pdo);
            break;

        case 'me':
            if ($method !== 'GET') error_response('Method not allowed', 405);
            hr_set_user(require_auth());
            auth_me($pdo);
            break;

        case 'logout':
            if ($method !== 'POST') error_response('Method not allowed', 405);
            auth_logout($pdo);
            break;

        case 'profile':
            if ($method !== 'PUT') error_response('Method not allowed', 405);
            hr_set_user(require_auth());
            auth_update_profile($body, $pdo);
            break;

        case 'password':
            if ($method !== 'PUT') error_response('Method not allowed', 405);
            hr_set_user(require_auth());
            auth_change_password($body, $pdo);
            break;

        case 'webauthn':          // passkeys: Windows Hello / fingerprint / face (api/webauthn.php)
            require_once __DIR__ . '/webauthn.php';
            handle_auth_webauthn($sub, $method, $body, $pdo);
            break;

        default:
            error_response('Not found', 404);
    }
}

// ------------------------------------------------------------------ helpers

function auth_client_ip(): string {
    return substr((string)($_SERVER['REMOTE_ADDR'] ?? 'unknown'), 0, 45);
}

/** Password rules for new passwords. */
function auth_check_password_strength(string $password): void {
    if (strlen($password) < 8) {
        error_response('Password must be at least 8 characters', 422);
    }
}

/** Sanitised user payload sent to clients (no hash, includes permissions and team-lead flag). */
function auth_user_payload(PDO $pdo, array $user): array {
    $permStmt = $pdo->prepare("SELECT module, enabled FROM user_permissions WHERE user_id = ?");
    $permStmt->execute([$user['id']]);
    unset($user['password_hash'], $user['token'], $user['session_expires'], $user['company_status']);
    $user['permissions'] = $permStmt->fetchAll();
    if (!empty($user['is_away'])) {
        // Working in another company of the group: the permissions of the home company do not apply; show what the grant allows
        $mods = $user['access_modules'] ?? null;
        $user['permissions'] = is_array($mods)
            ? array_map(fn($m) => ['module' => $m, 'enabled' => in_array($m, $mods, true) ? 1 : 0], GROUP_MODULES)
            : [];
    }

    $isLead = false;
    if (!empty($user['employee_id'])) {
        $s = $pdo->prepare("SELECT 1 FROM employees WHERE company_id = ? AND manager_id = ? AND status != 'inactive' LIMIT 1");
        $s->execute([$user['company_id'], $user['employee_id']]);
        $isLead = (bool)$s->fetchColumn();
    }
    $user['is_team_lead'] = $isLead;
    require_once __DIR__ . '/../helpers/identity.php';
    $user['email'] = email_public($user['email'] ?? '');
    return $user;
}

function auth_session_response(PDO $pdo, array $user, int $status = 200): void {
    app_lock_assert_company($pdo, (int)$user['company_id']);   // single-company editions
    $company = company_get($pdo, (int)$user['company_id']);
    cleanup_expired_sessions($pdo);
    $token = create_session($pdo, (int)$user['id']);
    $pdo->prepare("UPDATE users SET last_login_at = NOW() WHERE id = ?")->execute([$user['id']]);
    json_response([
        'success' => true,
        'token'   => $token,
        'user'    => auth_user_payload($pdo, $user),
        'company' => $company ? company_public($company) : null,
        'group'   => group_context_payload($pdo, $user),      // null unless the company is part of a group
    ], $status);
}

// ------------------------------------------------------------------- login

function auth_login(array $body, PDO $pdo): void {
    require_once __DIR__ . '/../helpers/identity.php';
    $email    = identity_to_email($pdo, (string)($body['email'] ?? ''));      // an e-mail address or a mobile number
    $password = (string)($body['password'] ?? '');

    if ($email === '' || $password === '') {
        error_response('Email and password are required');
    }

    // Slow down guessing: 8 failures per e-mail (or 30 per IP) in 15 minutes
    if (throttle_count($pdo, 'login:' . $email, 15) >= 8 || throttle_count($pdo, 'loginip:' . auth_client_ip(), 15) >= 30) {
        error_response('Too many failed attempts. Please try again in 15 minutes.', 429);
    }

    $stmt = $pdo->prepare("SELECT u.*, c.status AS company_status FROM users u JOIN companies c ON c.id = u.company_id WHERE u.email = ? LIMIT 1");
    $stmt->execute([$email]);
    $user = $stmt->fetch();

    if (!$user || !password_verify($password, $user['password_hash'])) {
        throttle_hit($pdo, 'login:' . $email);
        throttle_hit($pdo, 'loginip:' . auth_client_ip());
        error_response('Invalid email or password', 401);
    }
    if ($user['status'] === 'active' && $user['role'] === 'employee' && !empty($user['employee_id'])) {
        // a planned closing whose time has passed applies before the person gets in
        require_once __DIR__ . '/../helpers/certificates.php';
        hr_set_user($user);
        exit_apply_due($pdo);
        $re = $pdo->prepare("SELECT status FROM users WHERE id = ?");
        $re->execute([$user['id']]);
        $user['status'] = (string)$re->fetchColumn();
    }
    if ($user['status'] !== 'active') {
        error_response('Your account is not active. Please contact HR.', 403);
    }
    if ($user['company_status'] !== 'active') {
        error_response('This company account is suspended.', 403);
    }

    throttle_clear($pdo, 'login:' . $email);
    auth_session_response($pdo, $user);
}

function auth_me(PDO $pdo): void {
    $user = me();
    $company = company_get($pdo, (int)$user['company_id']);
    json_response([
        'success' => true,
        // The response normalizer unwraps `user`, so the company travels inside it.
        'user'    => array_merge(auth_user_payload($pdo, $user), [
            'company' => $company ? company_public($company) : null,
            'group'   => group_context_payload($pdo, $user),
        ]),
    ]);
}

function auth_logout(PDO $pdo): void {
    $token = get_bearer_token();
    if ($token) {
        delete_session($pdo, $token);
    }
    json_response(['success' => true, 'message' => 'Logged out successfully']);
}

// --------------------------------------------------- user management / profile

function auth_register(array $body, PDO $pdo): void {
    $name     = trim($body['name'] ?? '');
    $email    = strtolower(trim($body['email'] ?? ''));
    $password = (string)($body['password'] ?? '');
    $role     = $body['role'] ?? 'hr_manager';

    if ($name === '' || $email === '' || $password === '') {
        error_response('Name, email, and password are required');
    }
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) error_response('Invalid email address', 422);
    auth_check_password_strength($password);
    if (!in_array($role, ['hr_admin', 'hr_manager'], true)) {
        error_response('Invalid role. Must be hr_admin or hr_manager', 422);
    }

    $check = $pdo->prepare("SELECT id FROM users WHERE email = ? LIMIT 1");
    $check->execute([$email]);
    if ($check->fetch()) {
        error_response('A user with this email already exists', 409);
    }

    $pdo->prepare(
        "INSERT INTO users (company_id, name, email, password_hash, role, title, phone, status, created_by, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'active', ?, NOW())"
    )->execute([cid(), $name, $email, password_hash($password, PASSWORD_BCRYPT), $role, $body['title'] ?? null, $body['phone'] ?? null, (int)me()['id']]);
    $userId = (int)$pdo->lastInsertId();

    if (!empty($body['permissions']) && is_array($body['permissions'])) {
        $permStmt = $pdo->prepare(
            "INSERT INTO user_permissions (user_id, module, enabled) VALUES (?, ?, ?)
             ON DUPLICATE KEY UPDATE enabled = VALUES(enabled)"
        );
        foreach ($body['permissions'] as $perm) {
            $module = preg_replace('/[^a-z_]/', '', strtolower((string)($perm['module'] ?? '')));
            if ($module !== '') $permStmt->execute([$userId, $module, isset($perm['enabled']) ? (int)$perm['enabled'] : 1]);
        }
    }

    $newUser = $pdo->prepare("SELECT id, name, email, role, title, phone, status, created_at FROM users WHERE id = ?");
    $newUser->execute([$userId]);
    json_response(['success' => true, 'user' => $newUser->fetch()], 201);
}

function auth_update_profile(array $body, PDO $pdo): void {
    $user   = me();
    $fields = [];
    $params = [];

    // Employees may only change their photo; everything else is managed by HR (they send a change request).
    if (($user['role'] ?? '') === 'employee') {
        foreach (['name', 'title', 'phone'] as $locked) {
            if (isset($body[$locked])) error_response('Your information is managed by HR. Send a change request instead.', 403);
        }
    }

    foreach (['name' => 'name', 'avatar' => 'avatar', 'title' => 'title', 'phone' => 'phone'] as $in => $col) {
        if (isset($body[$in])) {
            $fields[] = "$col = ?";
            $params[]  = $in === 'name' ? trim((string)$body[$in]) : $body[$in];
        }
    }
    if (empty($fields)) {
        error_response('No fields to update');
    }

    $params[] = $user['id'];
    $pdo->prepare("UPDATE users SET " . implode(', ', $fields) . " WHERE id = ?")->execute($params);

    // Keep the linked employee record in step for the fields they share
    if (!empty($user['employee_id'])) {
        $emp = [];
        $ep  = [];
        if (isset($body['phone']))  { $emp[] = 'phone = ?';  $ep[] = $body['phone']; }
        if (isset($body['avatar'])) { $emp[] = 'avatar = ?'; $ep[] = $body['avatar']; }
        if ($emp) {
            $ep[] = $user['employee_id'];
            $ep[] = cid();
            $pdo->prepare("UPDATE employees SET " . implode(', ', $emp) . " WHERE id = ? AND company_id = ?")->execute($ep);
        }
    }

    $stmt = $pdo->prepare("SELECT id, name, email, role, avatar, title, phone, status, employee_id, company_id FROM users WHERE id = ?");
    $stmt->execute([$user['id']]);
    json_response(['success' => true, 'user' => $stmt->fetch()]);
}

function auth_change_password(array $body, PDO $pdo): void {
    $user        = me();
    $oldPassword = (string)($body['old_password'] ?? $body['current_password'] ?? '');
    $newPassword = (string)($body['new_password'] ?? '');

    if ($oldPassword === '' || $newPassword === '') {
        error_response('Old password and new password are required');
    }
    auth_check_password_strength($newPassword);

    $stmt = $pdo->prepare("SELECT password_hash FROM users WHERE id = ?");
    $stmt->execute([$user['id']]);
    $row = $stmt->fetch();
    if (!$row || !password_verify($oldPassword, $row['password_hash'])) {
        error_response('Current password is incorrect', 401);
    }

    $pdo->prepare("UPDATE users SET password_hash = ? WHERE id = ?")->execute([password_hash($newPassword, PASSWORD_BCRYPT), $user['id']]);
    // Sign out every other device
    $pdo->prepare("DELETE FROM sessions WHERE user_id = ? AND token != ?")->execute([$user['id'], get_bearer_token()]);

    json_response(['success' => true, 'message' => 'Password changed successfully']);
}

// ------------------------------------------------------------ company sign-up

function auth_slugify(string $name): string {
    $slug = strtolower(trim(preg_replace('/[^a-zA-Z0-9]+/', '-', $name), '-'));
    return $slug !== '' ? substr($slug, 0, 60) : 'company';
}

/** Public: create a company and its first admin. */
function auth_register_company(array $body, PDO $pdo): void {
    if (throttle_count($pdo, 'signup:' . auth_client_ip(), 60) >= 5) {
        error_response('Too many sign-ups from this network. Please try again later.', 429);
    }

    $company = trim($body['company_name'] ?? '');
    $name    = trim($body['name'] ?? '');
    $email   = strtolower(trim($body['email'] ?? ''));
    $password = (string)($body['password'] ?? '');

    if ($company === '' || $name === '' || $email === '' || $password === '') {
        error_response('company_name, name, email and password are required', 422);
    }
    if (mb_strlen($company) > 120 || mb_strlen($name) > 120) error_response('Name is too long', 422);
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) error_response('Invalid email address', 422);
    auth_check_password_strength($password);

    $exists = $pdo->prepare("SELECT 1 FROM users WHERE email = ? UNION SELECT 1 FROM employees WHERE email = ? LIMIT 1");
    $exists->execute([$email, $email]);
    if ($exists->fetchColumn()) error_response('An account with this email already exists', 409);

    $tz = $body['timezone'] ?? 'Africa/Cairo';
    if (!in_array($tz, timezone_identifiers_list(), true)) $tz = 'Africa/Cairo';
    $currency = strtoupper(substr(preg_replace('/[^A-Za-z]/', '', (string)($body['currency'] ?? 'EGP')), 0, 3)) ?: 'EGP';

    $slug = auth_slugify($company);
    $base = $slug; $i = 1;
    $chk = $pdo->prepare("SELECT 1 FROM companies WHERE slug = ?");
    while (true) {
        $chk->execute([$slug]);
        if (!$chk->fetchColumn()) break;
        $slug = $base . '-' . (++$i);
    }

    throttle_hit($pdo, 'signup:' . auth_client_ip());

    $pdo->beginTransaction();
    try {
        $pdo->prepare("INSERT INTO companies (name, slug, timezone, currency) VALUES (?, ?, ?, ?)")->execute([$company, $slug, $tz, $currency]);
        $companyId = (int)$pdo->lastInsertId();

        $pdo->prepare(
            "INSERT INTO users (company_id, name, email, password_hash, role, status, phone, created_at)
             VALUES (?, ?, ?, ?, 'hr_admin', 'active', ?, NOW())"
        )->execute([$companyId, $name, $email, password_hash($password, PASSWORD_BCRYPT), $body['phone'] ?? null]);
        $userId = (int)$pdo->lastInsertId();

        // Sensible defaults so the new company can start straight away
        company_seed_defaults($pdo, $companyId);
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        error_log('[HR API] company sign-up failed: ' . $e->getMessage());
        error_response('Could not create the company. Please try again.', 500);
    }

    $u = $pdo->prepare("SELECT u.*, c.status AS company_status FROM users u JOIN companies c ON c.id = u.company_id WHERE u.id = ?");
    $u->execute([$userId]);
    auth_session_response($pdo, $u->fetch(), 201);
}

// -------------------------------------------------- employee self-service auth

function handle_auth_employee(string $action, string $method, array $body, PDO $pdo): void {
    if ($method !== 'POST') error_response('Method not allowed', 405);

    switch ($action) {
        case 'check-email':     auth_employee_check_email($body, $pdo); break;
        case 'activate':        auth_employee_activate($body, $pdo); break;
        case 'login':           auth_login($body, $pdo); break;
        case 'forgot-password': auth_employee_forgot_password($body, $pdo); break;
        case 'reset-password':  auth_employee_reset_password($body, $pdo); break;
        default:                error_response('Not found', 404);
    }
}

function auth_employee_check_email(array $body, PDO $pdo): void {
    require_once __DIR__ . '/../helpers/identity.php';
    $email = identity_to_email($pdo, (string)($body['email'] ?? ''));
    if ($email === '') {
        error_response('Email is required');
    }
    if (throttle_count($pdo, 'checkip:' . auth_client_ip(), 10) >= 40) {
        error_response('Too many requests. Please try again in a few minutes.', 429);
    }
    throttle_hit($pdo, 'checkip:' . auth_client_ip());

    // HR staff sign in with their password directly
    $hr = $pdo->prepare("SELECT company_id FROM users WHERE email = ? AND role IN ('hr_admin', 'hr_manager') AND status = 'active' LIMIT 1");
    $hr->execute([$email]);
    $hrCompany = $hr->fetchColumn();
    if ($hrCompany !== false && app_lock_allows($pdo, (int)$hrCompany)) {   // locked editions only see their own company
        json_response(['status' => 'hr']);
        return;
    }

    $emp = $pdo->prepare("SELECT id, company_id FROM employees WHERE email = ? AND status != 'inactive' LIMIT 1");
    $emp->execute([$email]);
    $employee = $emp->fetch();
    if (!$employee || !app_lock_allows($pdo, (int)$employee['company_id'])) {
        json_response(['status' => 'not_found']);
        return;
    }

    $u = $pdo->prepare("SELECT status FROM users WHERE email = ? AND role = 'employee' LIMIT 1");
    $u->execute([$email]);
    $user = $u->fetch();

    json_response([
        'status'      => ($user && $user['status'] === 'active') ? 'active' : 'needs_activation',
        'employee_id' => (int)$employee['id'],
    ]);
}

/** Validate an invitation code for an employee; consumes it when valid. */
function auth_use_invitation(PDO $pdo, int $employeeId, string $purpose, string $code): void {
    $s = $pdo->prepare(
        "SELECT * FROM invitations WHERE employee_id = ? AND purpose = ? AND used_at IS NULL AND expires_at > NOW()
         ORDER BY id DESC LIMIT 1"
    );
    $s->execute([$employeeId, $purpose]);
    $inv = $s->fetch();

    if (!$inv || (int)$inv['attempts'] >= 5) {
        error_response('This code is invalid or has expired. Please ask HR for a new one.', 422);
    }
    if (!hash_equals($inv['code_hash'], hash('sha256', preg_replace('/\D/', '', $code)))) {
        $pdo->prepare("UPDATE invitations SET attempts = attempts + 1 WHERE id = ?")->execute([$inv['id']]);
        error_response('Incorrect code. Please check it and try again.', 422);
    }
    $pdo->prepare("UPDATE invitations SET used_at = NOW() WHERE id = ?")->execute([$inv['id']]);
}

function auth_employee_activate(array $body, PDO $pdo): void {
    require_once __DIR__ . '/../helpers/identity.php';
    $email    = identity_to_email($pdo, (string)($body['email'] ?? ''));
    $password = (string)($body['password'] ?? '');
    $code     = (string)($body['code'] ?? '');

    if ($email === '' || $password === '' || $code === '') {
        error_response('Email, invite code and password are required');
    }
    auth_check_password_strength($password);
    if (throttle_count($pdo, 'activate:' . auth_client_ip(), 15) >= 15) {
        error_response('Too many attempts. Please try again later.', 429);
    }
    throttle_hit($pdo, 'activate:' . auth_client_ip());

    $emp = $pdo->prepare("SELECT * FROM employees WHERE email = ? AND status != 'inactive' LIMIT 1");
    $emp->execute([$email]);
    $employee = $emp->fetch();
    if (!$employee) {
        error_response('No employee found with this email', 404);
    }

    $check = $pdo->prepare("SELECT id FROM users WHERE email = ? LIMIT 1");
    $check->execute([$email]);
    if ($check->fetch()) {
        error_response('An account for this email already exists. Please sign in.', 409);
    }

    auth_use_invitation($pdo, (int)$employee['id'], 'activate', $code);

    $pdo->prepare(
        "INSERT INTO users (company_id, name, email, password_hash, role, status, employee_id, phone, phone_key, avatar, created_at)
         VALUES (?, ?, ?, ?, 'employee', 'active', ?, ?, ?, ?, NOW())"
    )->execute([
        $employee['company_id'], $employee['first_name'] . ' ' . $employee['last_name'], $email,
        password_hash($password, PASSWORD_BCRYPT), $employee['id'], $employee['phone'], phone_key($employee['phone']), $employee['avatar'],
    ]);
    $userId = (int)$pdo->lastInsertId();

    $u = $pdo->prepare("SELECT u.*, c.status AS company_status FROM users u JOIN companies c ON c.id = u.company_id WHERE u.id = ?");
    $u->execute([$userId]);
    auth_session_response($pdo, $u->fetch(), 201);
}

function auth_employee_forgot_password(array $body, PDO $pdo): void {
    require_once __DIR__ . '/../helpers/identity.php';
    // Always the same answer, so nobody can find out which e-mail addresses or numbers have an account.
    $generic = ['success' => true, 'message' => 'If this account exists, a code has been sent to it. Otherwise ask your HR team for a reset code.'];
    $email = identity_to_email($pdo, (string)($body['email'] ?? ''));
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) json_response($generic);

    if (throttle_count($pdo, 'forgot-ip:' . auth_client_ip(), 60) >= 10 || throttle_count($pdo, 'forgot-mail:' . $email, 60) >= 3) json_response($generic);
    throttle_hit($pdo, 'forgot-ip:' . auth_client_ip());
    throttle_hit($pdo, 'forgot-mail:' . $email);

    $u = $pdo->prepare("SELECT u.id, u.company_id, u.phone FROM users u WHERE u.email = ? AND u.status = 'active' LIMIT 1");
    $u->execute([$email]);
    $user = $u->fetch();
    if ($user) {
        $code = str_pad((string)random_int(0, 999999), 6, '0', STR_PAD_LEFT);
        $pdo->prepare("UPDATE password_resets SET used_at = NOW() WHERE user_id = ? AND used_at IS NULL")->execute([$user['id']]);
        $pdo->prepare("INSERT INTO password_resets (user_id, code_hash, expires_at) VALUES (?, ?, (NOW() + INTERVAL 30 MINUTE))")
            ->execute([$user['id'], hash('sha256', $code)]);
        $c = $pdo->prepare("SELECT name FROM companies WHERE id = ?");
        $c->execute([$user['company_id']]);
        $company = (string)($c->fetchColumn() ?: 'Al Anad HR');
        // by e-mail, or by SMS when the person asks for it (and has a mobile number on the account)
        $bySms = (($body['via'] ?? '') === 'sms') && phone_valid($user['phone']);
        if (!$bySms && email_is_real($email)) {
            require_once __DIR__ . '/../helpers/mailer.php';
            mail_send_code($email, $company, 'reset', $code, '30 minutes');
        } elseif (phone_valid($user['phone'])) {
            require_once __DIR__ . '/../helpers/sms.php';
            sms_send($user['phone'], sms_reset_text($company, $code));
        }
    } else {
        // First sign-in: there is no account yet, so "send me a code" means "send my invitation again".
        auth_resend_activation($pdo, $email, ($body['via'] ?? '') === 'sms');
    }
    json_response($generic);
}

/**
 * The person is on the first-time screen and asks for a code: issue a new one-time invitation code for their employee
 * record (the old ones stop working) and send it by e-mail or SMS. Silent when the person is unknown or already has an account.
 */
function auth_resend_activation(PDO $pdo, string $email, bool $viaSms): void {
    $e = $pdo->prepare("SELECT id, company_id, email, phone FROM employees WHERE email = ? AND status != 'inactive' LIMIT 1");
    $e->execute([$email]);
    $emp = $e->fetch();
    if (!$emp || !app_lock_allows($pdo, (int)$emp['company_id'])) return;
    $has = $pdo->prepare("SELECT 1 FROM users WHERE email = ? OR (employee_id = ? AND role = 'employee') LIMIT 1");
    $has->execute([$email, $emp['id']]);
    if ($has->fetchColumn()) return;

    $days = 7;
    $pdo->prepare("UPDATE invitations SET used_at = NOW() WHERE employee_id = ? AND purpose = 'activate' AND used_at IS NULL")->execute([$emp['id']]);
    $code = str_pad((string)random_int(0, 999999), 6, '0', STR_PAD_LEFT);
    $pdo->prepare("INSERT INTO invitations (company_id, employee_id, purpose, code_hash, expires_at, created_by) VALUES (?, ?, 'activate', ?, (NOW() + INTERVAL $days DAY), NULL)")
        ->execute([$emp['company_id'], $emp['id'], hash('sha256', $code)]);
    $c = $pdo->prepare("SELECT name FROM companies WHERE id = ?");
    $c->execute([$emp['company_id']]);
    $company = (string)($c->fetchColumn() ?: 'Al Anad HR');

    $hasMail = email_is_real($emp['email'] ?? '');
    if ((!$viaSms || !phone_valid($emp['phone'])) && $hasMail) {
        require_once __DIR__ . '/../helpers/mailer.php';
        mail_send_code((string)$emp['email'], $company, 'activate', $code, "$days days", (string)$emp['email']);
    } elseif (phone_valid($emp['phone'])) {
        require_once __DIR__ . '/../helpers/sms.php';
        sms_send($emp['phone'], sms_invite_text($company, (string)$emp['phone'], $code, "$days days"));
    }
}

function auth_employee_reset_password(array $body, PDO $pdo): void {
    require_once __DIR__ . '/../helpers/identity.php';
    $email       = identity_to_email($pdo, (string)($body['email'] ?? ''));
    $code        = (string)($body['code'] ?? $body['reset_token'] ?? $body['token'] ?? '');
    $newPassword = (string)($body['new_password'] ?? $body['password'] ?? '');

    if ($email === '' || $code === '' || $newPassword === '') {
        error_response('Email, reset code and new password are required');
    }
    auth_check_password_strength($newPassword);
    if (throttle_count($pdo, 'reset:' . auth_client_ip(), 15) >= 15) {
        error_response('Too many attempts. Please try again later.', 429);
    }
    throttle_hit($pdo, 'reset:' . auth_client_ip());

    $u = $pdo->prepare("SELECT u.id, u.employee_id, u.role FROM users u WHERE u.email = ? AND u.status = 'active' LIMIT 1");
    $u->execute([$email]);
    $user = $u->fetch();
    if (!$user) {
        error_response('This code is invalid or has expired. Please request a new one.', 422);
    }

    // 1) a code that was e-mailed to the account owner (any account type)
    $usedMailed = false;
    $r = $pdo->prepare("SELECT * FROM password_resets WHERE user_id = ? AND used_at IS NULL AND expires_at > NOW() ORDER BY id DESC LIMIT 1");
    $r->execute([$user['id']]);
    $reset = $r->fetch();
    if ($reset && (int)$reset['attempts'] < 5) {
        if (hash_equals($reset['code_hash'], hash('sha256', preg_replace('/\D/', '', $code)))) {
            $pdo->prepare("UPDATE password_resets SET used_at = NOW() WHERE id = ?")->execute([$reset['id']]);
            $usedMailed = true;
        } else {
            $pdo->prepare("UPDATE password_resets SET attempts = attempts + 1 WHERE id = ?")->execute([$reset['id']]);
        }
    }
    // 2) otherwise a one-time code given by HR (employees only)
    if (!$usedMailed) {
        if ($user['role'] !== 'employee' || (int)$user['employee_id'] <= 0) {
            error_response('This code is invalid or has expired. Please request a new one.', 422);
        }
        auth_use_invitation($pdo, (int)$user['employee_id'], 'reset', $code);
    }

    $pdo->prepare("UPDATE users SET password_hash = ? WHERE id = ?")->execute([password_hash($newPassword, PASSWORD_BCRYPT), $user['id']]);
    $pdo->prepare("DELETE FROM sessions WHERE user_id = ?")->execute([$user['id']]);
    json_response(['success' => true, 'message' => 'Password reset successfully']);
}
