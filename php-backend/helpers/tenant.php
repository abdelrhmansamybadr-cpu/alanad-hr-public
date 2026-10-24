<?php
/**
 * Multi-company context, roles and notifications.
 *
 * index.php authenticates the request and calls hr_set_user(); after that every
 * handler uses cid() to scope its queries to the caller's company and me()
 * for the current user. Nothing outside the caller's company is ever readable
 * or writable through the API.
 */

$GLOBALS['HR_USER'] = null;

function hr_set_user(array $user): void {
    $GLOBALS['HR_USER'] = $user;
}

/** The authenticated user row (no password hash). */
function me(): array {
    if (!$GLOBALS['HR_USER']) {
        error_response('Unauthorized. Please log in.', 401);
    }
    return $GLOBALS['HR_USER'];
}

/** Company id of the authenticated caller. */
function cid(): int {
    return (int)me()['company_id'];
}

function is_admin(): bool { return (me()['role'] ?? '') === 'hr_admin'; }
function is_hr(): bool    { return in_array(me()['role'] ?? '', ['hr_admin', 'hr_manager'], true); }

function require_hr(): void {
    if (!is_hr()) error_response('Forbidden. Insufficient permissions.', 403);
}
function require_admin(): void {
    if (!is_admin()) error_response('Forbidden. Only company admins can do this.', 403);
}

/** Employee record id linked to the caller (0 when none). */
function own_employee_id(): int {
    return (int)(me()['employee_id'] ?? 0);
}

/** Is `$employeeId` in the caller's company? */
function employee_in_company(PDO $pdo, int $employeeId): bool {
    $s = $pdo->prepare("SELECT 1 FROM employees WHERE id = ? AND company_id = ? LIMIT 1");
    $s->execute([$employeeId, cid()]);
    return (bool)$s->fetchColumn();
}

/** Does the caller directly manage `$employeeId` (employees.manager_id)? */
function is_manager_of(PDO $pdo, int $employeeId): bool {
    $own = own_employee_id();
    if ($own <= 0) return false;
    $s = $pdo->prepare("SELECT 1 FROM employees WHERE id = ? AND company_id = ? AND manager_id = ? LIMIT 1");
    $s->execute([$employeeId, cid(), $own]);
    return (bool)$s->fetchColumn();
}

/** Does the caller manage anybody? (used to show team screens to team leads) */
function has_direct_reports(PDO $pdo): bool {
    $own = own_employee_id();
    if ($own <= 0) return false;
    $s = $pdo->prepare("SELECT 1 FROM employees WHERE company_id = ? AND manager_id = ? AND status != 'inactive' LIMIT 1");
    $s->execute([cid(), $own]);
    return (bool)$s->fetchColumn();
}

/** HR, or the direct manager of the employee, may review requests of that employee. */
function can_review_for(PDO $pdo, int $employeeId): bool {
    return is_hr() || is_manager_of($pdo, $employeeId);
}

// ---------------------------------------------------------------- modules

/** API root segment -> permission module used by the admin panel. */
function hr_module_for_route(string $root): ?string {
    static $map = [
        'employees' => 'employees', 'departments' => 'departments', 'leaves' => 'leaves',
        'attendance' => 'attendance', 'attendance-rules' => 'attendance', 'shifts' => 'shifts',
        'payroll' => 'payroll', 'jobs' => 'recruitment', 'applications' => 'recruitment',
        'recruitment' => 'recruitment', 'talent-pool' => 'talent_pool', 'reviews' => 'reviews',
        'announcements' => 'announcements', 'documents' => 'documents', 'hr-staff' => 'hr_staff',
        'requests' => 'requests', 'stats' => 'dashboard',
    ];
    return $map[$root] ?? null;
}

/** hr_manager accounts may have individual modules switched off (user_permissions.enabled = 0). */
function hr_manager_module_allowed(PDO $pdo, int $userId, string $module): bool {
    // Working in another company of the group with a 'custom' grant: only the modules chosen in that grant
    $u = $GLOBALS['HR_USER'] ?? null;
    if ($u && !empty($u['is_away'])) {
        $mods = $u['access_modules'] ?? null;      // null = every module
        return $mods === null || in_array($module, $mods, true);
    }
    $s = $pdo->prepare("SELECT enabled FROM user_permissions WHERE user_id = ? AND module = ? LIMIT 1");
    $s->execute([$userId, $module]);
    $row = $s->fetch();
    return $row === false ? true : (bool)$row['enabled'];
}

// ---------------------------------------------------------------- company

function company_get(PDO $pdo, int $id): ?array {
    $s = $pdo->prepare("SELECT * FROM companies WHERE id = ? LIMIT 1");
    $s->execute([$id]);
    $c = $s->fetch();
    return $c ?: null;
}

/** Branding + settings the apps need at start-up. */
function company_public(array $c): array {
    $modules = null;
    if (!empty($c['modules'])) {
        $decoded = json_decode($c['modules'], true);
        if (is_array($decoded)) $modules = array_values($decoded);
    }
    return [
        'id'               => (int)$c['id'],
        'name'             => $c['name'],
        'slug'             => $c['slug'],
        'logo_url'         => $c['logo_url'],
        'primary_color'    => $c['primary_color'],
        'accent_color'     => $c['accent_color'],
        'timezone'         => $c['timezone'],
        'currency'         => $c['currency'],
        'weekend_days'     => $c['weekend_days'],
        'language'         => $c['language'],
        'late_grace_minutes' => (int)$c['late_grace_minutes'],
        'modules'          => $modules,          // null = every module enabled
        'plan'             => $c['plan'],
        'features'         => function_exists('feature_flags') ? feature_flags(getDB(), (int)$c['id']) : [],   // owner-controlled premium switches
        'attendance_policy' => policy_from_row($c, 'attendance_policy', att_policy_defaults()),
        'points_config'     => policy_from_row($c, 'points_config', points_config_defaults()),
        'payroll_policy'    => policy_from_row($c, 'payroll_policy', payroll_policy_defaults()),
    ];
}

// ---------------------------------------------------------- notifications

function notify(PDO $pdo, int $companyId, int $userId, string $type, string $title, ?string $body = null, ?array $data = null): void {
    $pdo->prepare(
        "INSERT INTO notifications (company_id, user_id, type, title, body, data) VALUES (?, ?, ?, ?, ?, ?)"
    )->execute([$companyId, $userId, $type, $title, $body, $data ? json_encode($data) : null]);
}

/** Notify every active HR user of the company (except `$exceptUserId`). */
function notify_hr(PDO $pdo, string $type, string $title, ?string $body = null, ?array $data = null, ?int $exceptUserId = null): void {
    $s = $pdo->prepare("SELECT id FROM users WHERE company_id = ? AND role IN ('hr_admin','hr_manager') AND status = 'active'");
    $s->execute([cid()]);
    foreach ($s->fetchAll(PDO::FETCH_COLUMN) as $uid) {
        if ($exceptUserId !== null && (int)$uid === $exceptUserId) continue;
        notify($pdo, cid(), (int)$uid, $type, $title, $body, $data);
    }
}

/** Notify the user account(s) linked to an employee record. */
function notify_employee(PDO $pdo, int $employeeId, string $type, string $title, ?string $body = null, ?array $data = null): void {
    $s = $pdo->prepare("SELECT id FROM users WHERE company_id = ? AND employee_id = ? AND status = 'active'");
    $s->execute([cid(), $employeeId]);
    foreach ($s->fetchAll(PDO::FETCH_COLUMN) as $uid) {
        notify($pdo, cid(), (int)$uid, $type, $title, $body, $data);
    }
}

/** Notify the direct manager of an employee (if any and if they have an account). */
function notify_manager_of(PDO $pdo, int $employeeId, string $type, string $title, ?string $body = null, ?array $data = null): void {
    $s = $pdo->prepare("SELECT manager_id FROM employees WHERE id = ? AND company_id = ?");
    $s->execute([$employeeId, cid()]);
    $mid = (int)$s->fetchColumn();
    if ($mid > 0) notify_employee($pdo, $mid, $type, $title, $body, $data);
}

/** Notify everyone in the company. */
function notify_company(PDO $pdo, string $type, string $title, ?string $body = null, ?array $data = null, ?int $exceptUserId = null): void {
    $s = $pdo->prepare("SELECT id FROM users WHERE company_id = ? AND status = 'active'");
    $s->execute([cid()]);
    foreach ($s->fetchAll(PDO::FETCH_COLUMN) as $uid) {
        if ($exceptUserId !== null && (int)$uid === $exceptUserId) continue;
        notify($pdo, cid(), (int)$uid, $type, $title, $body, $data);
    }
}

// ------------------------------------------------------------------ misc

/** Does row `$id` of `$table` exist in the caller's company? ($table is always a literal.) */
function in_company(PDO $pdo, string $table, ?int $id): bool {
    if (!$id) return false;
    $s = $pdo->prepare("SELECT 1 FROM `$table` WHERE id = ? AND company_id = ? LIMIT 1");
    $s->execute([$id, cid()]);
    return (bool)$s->fetchColumn();
}

/** Positive int from user input, or null. */
function int_or_null($v): ?int {
    return (isset($v) && $v !== '' && is_numeric($v) && (int)$v > 0) ? (int)$v : null;
}

// ------------------------------------------------------------ rate limiting

/** Record one hit for a throttle key (e.g. "login:user@example.com"). */
function throttle_hit(PDO $pdo, string $key): void {
    $pdo->prepare("INSERT INTO throttle (k, created_at) VALUES (?, NOW())")->execute([substr($key, 0, 190)]);
    if (mt_rand(1, 50) === 1) {            // opportunistic cleanup
        $pdo->exec("DELETE FROM throttle WHERE created_at < (NOW() - INTERVAL 1 DAY)");
    }
}

/** Hits for a key within the last `$minutes` minutes. */
function throttle_count(PDO $pdo, string $key, int $minutes): int {
    $s = $pdo->prepare("SELECT COUNT(*) FROM throttle WHERE k = ? AND created_at > (NOW() - INTERVAL $minutes MINUTE)");
    $s->execute([substr($key, 0, 190)]);
    return (int)$s->fetchColumn();
}

function throttle_clear(PDO $pdo, string $key): void {
    $pdo->prepare("DELETE FROM throttle WHERE k = ?")->execute([substr($key, 0, 190)]);
}

// ------------------------------------------------------------- invitations

/**
 * Create a one-time 6-digit code for an employee ('activate' = first sign-in,
 * 'reset' = forgotten password). Returns the plain code — it is shown to HR once
 * and only its hash is stored.
 */
function invitation_create(PDO $pdo, int $employeeId, string $purpose, int $days = 7): string {
    $pdo->prepare("UPDATE invitations SET used_at = NOW() WHERE employee_id = ? AND purpose = ? AND used_at IS NULL")->execute([$employeeId, $purpose]);
    $code = str_pad((string)random_int(0, 999999), 6, '0', STR_PAD_LEFT);
    $pdo->prepare(
        "INSERT INTO invitations (company_id, employee_id, purpose, code_hash, expires_at, created_by)
         VALUES (?, ?, ?, ?, (NOW() + INTERVAL $days DAY), ?)"
    )->execute([cid(), $employeeId, $purpose, hash('sha256', $code), (int)me()['id']]);
    return $code;
}

/** Is a module enabled for the caller's company? (companies.modules NULL = everything.) */
function company_module_enabled(PDO $pdo, string $module): bool {
    static $mods = false;
    if ($mods === false) {
        $c = company_get($pdo, cid());
        $decoded = ($c && !empty($c['modules'])) ? json_decode($c['modules'], true) : null;
        $mods = is_array($decoded) ? $decoded : null;
    }
    // Core modules are always on
    if ($mods === null || in_array($module, ['dashboard', 'hr_staff'], true)) return true;
    return in_array($module, $mods, true);
}
