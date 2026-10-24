<?php
/**
 * Extract the Bearer token from the Authorization header.
 *
 * @return string|null
 */
function get_bearer_token(): ?string {
    $headers = null;

    if (isset($_SERVER['HTTP_AUTHORIZATION'])) {
        $headers = $_SERVER['HTTP_AUTHORIZATION'];
    } elseif (isset($_SERVER['Authorization'])) {
        $headers = $_SERVER['Authorization'];
    } elseif (function_exists('apache_request_headers')) {
        $requestHeaders = apache_request_headers();
        $requestHeaders = array_combine(
            array_map('ucwords', array_keys($requestHeaders)),
            array_values($requestHeaders)
        );
        if (isset($requestHeaders['Authorization'])) {
            $headers = $requestHeaders['Authorization'];
        }
    }

    if ($headers === null) {
        return null;
    }

    if (preg_match('/Bearer\s+(.+)$/i', $headers, $matches)) {
        return trim($matches[1]);
    }

    return null;
}

/**
 * Validate the bearer token from the sessions table and return the user.
 *
 * @return array|null  User row or null if invalid/expired
 */
function get_authenticated_user(): ?array {
    $token = get_bearer_token();
    if (!$token) {
        return null;
    }

    try {
        $pdo = getDB();
        $stmt = $pdo->prepare(
            "SELECT u.*, s.token, s.expires_at AS session_expires, s.active_company_id, c.status AS company_status
             FROM sessions s
             JOIN users u ON u.id = s.user_id
             JOIN companies c ON c.id = u.company_id
             WHERE s.token = ? AND s.expires_at > NOW() AND u.status = 'active'"
        );
        $stmt->execute([$token]);
        $user = $stmt->fetch();

        if (!$user) {
            return null;
        }

        // Company groups: the company the person is currently working in (home company unless switched and still allowed)
        if (function_exists('group_apply_context')) {
            $user = group_apply_context($pdo, $user, $user['active_company_id'] ? (int)$user['active_company_id'] : null, $token);
        }

        // Single-company editions (e.g. the Al Anad app) refuse people of other companies
        if (function_exists('app_lock_assert_company')) app_lock_assert_company($pdo, (int)$user['company_id']);

        // Remove sensitive fields
        unset($user['password_hash']);

        return $user;
    } catch (PDOException $e) {
        return null;
    }
}

/**
 * Require authentication. Exits with 401 if not authenticated.
 *
 * @return array  The authenticated user
 */
function require_auth(): array {
    $user = get_authenticated_user();
    if (!$user) {
        error_response('Unauthorized. Please log in.', 401);
    }
    return $user;
}

/**
 * Require a specific role. Exits with 403 if role does not match.
 *
 * @param array  $user  The authenticated user
 * @param string $role  Required role (or comma-separated roles)
 */
function require_role(array $user, string $role): void {
    $allowed = array_map('trim', explode(',', $role));
    if (!in_array($user['role'], $allowed)) {
        error_response('Forbidden. Insufficient permissions.', 403);
    }
}

/**
 * Generate a secure random token.
 *
 * @return string 64-character hex token
 */
function generate_token(): string {
    return bin2hex(random_bytes(32));
}

/**
 * Create a session for the given user and return the token.
 *
 * @param PDO $pdo
 * @param int $user_id
 * @return string The session token
 */
function create_session(PDO $pdo, int $user_id): string {
    $token = generate_token();
    $expires_at = date('Y-m-d H:i:s', strtotime('+7 days'));
    $created_at = date('Y-m-d H:i:s');

    $stmt = $pdo->prepare(
        "INSERT INTO sessions (token, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)"
    );
    $stmt->execute([$token, $user_id, $expires_at, $created_at]);

    return $token;
}

/**
 * Delete a session by token.
 *
 * @param PDO    $pdo
 * @param string $token
 */
function delete_session(PDO $pdo, string $token): void {
    $stmt = $pdo->prepare("DELETE FROM sessions WHERE token = ?");
    $stmt->execute([$token]);
}

/**
 * Remove all expired sessions from the database.
 *
 * @param PDO $pdo
 */
function cleanup_expired_sessions(PDO $pdo): void {
    $pdo->exec("DELETE FROM sessions WHERE expires_at < NOW()");
}

/**
 * Does the row `$id` in `$table` belong to employee `$ownId` (and to the caller's company)?
 * $table is always a hard-coded literal from the callers below.
 */
function hr_owns_row(PDO $pdo, string $table, int $id, int $ownId): bool {
    $stmt = $pdo->prepare("SELECT 1 FROM `$table` WHERE id = ? AND employee_id = ? AND company_id = ? LIMIT 1");
    $stmt->execute([$id, $ownId, cid()]);
    return (bool)$stmt->fetchColumn();
}

/**
 * Access control for accounts with role 'employee'.
 * They may only reach their own records; everything not listed is forbidden.
 * $body and $_GET are rewritten so handlers can only ever see the caller's employee_id.
 * Handlers that allow team leads (leaves, requests, team) do their own per-row checks.
 */
function hr_enforce_employee_scope(string $root, array $seg, string $method, array &$body, int $ownId, PDO $pdo): void {
    $deny = function (): void { error_response('Forbidden. Insufficient permissions.', 403); };
    $sub  = $seg[1] ?? '';
    $id   = ($sub !== '' && ctype_digit($sub)) ? intval($sub) : null;

    // Read-only, company-wide, non-sensitive data every employee may see
    if (in_array($root, ['announcements', 'attendance-rules', 'holidays', 'leave-types', 'company', 'directory', 'org'], true)) {
        if ($method === 'GET') return;
        $deny();
    }
    if ($root === 'notifications') return;      // always scoped to the caller inside the handler
    if ($root === 'profile') return;            // caller's own profile only (handler)

    if ($ownId <= 0) {
        error_response('No employee record linked to this account', 403);
    }

    switch ($root) {
        case 'employees':                       // only their own profile and career history
            if ($method === 'GET' && $sub === 'me' && !isset($seg[2])) return;
            if ($method === 'GET' && $id === $ownId && ($seg[2] ?? '') === 'promotions') return;
            $deny();

        case 'assistant':                       // answers only from the caller's own records (handler)
            return;

        case 'labor-law':                       // read-only; the handler limits end-of-service to the caller's own record
            if ($method === 'GET') return;
            $deny();

        case 'decisions':                       // own decisions only (the handler scopes the list and decides who may answer)
            if ($method === 'GET' || ($method === 'POST' && ($seg[3] ?? '') === 'dispute')) return;
            if ($method === 'PUT' && ($seg[3] ?? '') === 'respond') return;      // a team lead answers their team's disputes; the handler checks who may
            $deny();

        case 'complaints':                      // team heads file and follow their own; the handler refuses everyone else (employees never see them)
            return;

        case 'coach':                           // read-only; the handler lets only HR and team leads in
            if ($method === 'GET') return;
            $deny();

        case 'field':                           // own visits; the handler lets managers see their team and HR everybody
            return;

        case 'career':                          // reading is open; the handler allows skills for team leads and everything else for HR only
            if ($method === 'GET') return;
            if ($method === 'PUT' && ($seg[3] ?? '') === 'skills') return;
            $deny();

        case 'arabic':                          // own letters / payslip link / voice: the handlers check ownership and role
            return;

        case 'meetings':                        // invited people join and call; the handler checks invitation / host rights
            return;

        case 'kudos':                           // everyone may read the feed and praise a colleague; the handler guards deletes
            return;

        case 'onboarding':                      // own checklist; the handler restricts ticking to the caller's own tasks
            if ($method === 'GET' && $sub === 'me') return;
            if ($method === 'PUT' && $sub === 'tasks') return;
            if ($method === 'POST' && $sub === 'event') return;     // the app reports a real action (signed, read, opened)
            $deny();

        case 'points':
            if ($method === 'GET' && in_array($sub, ['me', 'leaderboard', 'config'], true)) return;
            if ($method === 'GET' && $sub === 'employee' && isset($seg[2]) && ctype_digit($seg[2]) && intval($seg[2]) === $ownId) return;
            if ($method === 'GET' && $sub === 'employee' && has_direct_reports($pdo)) return;      // handler: reports only
            $deny();

        case 'attendance':
            if (in_array($sub, ['check-in', 'check-out', 'ping'], true) && $method === 'POST') return;     // handler uses own id
            if (in_array($sub, ['today', 'summary', 'explain'], true) && $method === 'GET') { $_GET['employee_id'] = $ownId; return; }
            if ($method === 'GET' && $id === null) { $_GET['employee_id'] = $ownId; return; }
            if ($method === 'GET' && $id !== null && hr_owns_row($pdo, 'attendance', $id, $ownId)) return;
            $deny();

        case 'shifts':
            if ($method === 'GET' && !isset($seg[2]) && $sub !== 'assign') return;
            $deny();

        case 'leaves':
            if ($method === 'GET' && $sub === 'policy') return;
            if ($method === 'GET' && $sub === 'balance') return;                            // handler: own balance
            if ($method === 'GET' && $id === null && $sub === '') {
                if (($_GET['scope'] ?? '') === 'team' && has_direct_reports($pdo)) return;  // handler limits to reports
                $_GET['employee_id'] = $ownId;
                return;
            }
            if ($method === 'GET' && $id !== null) return;                                  // handler: own or report
            if ($method === 'POST' && $sub === '') { $body['employee_id'] = $ownId; return; }
            if ($method === 'PUT' && $id !== null && has_direct_reports($pdo)) return;      // handler: report only
            if ($method === 'DELETE' && $id !== null && hr_owns_row($pdo, 'leaves', $id, $ownId)) return; // cancel own
            $deny();

        case 'requests':
            if ($method === 'GET' && $sub === '') {
                if (($_GET['scope'] ?? '') === 'team' && has_direct_reports($pdo)) return;
                $_GET['employee_id'] = $ownId;
                return;
            }
            if ($method === 'POST' && $sub === '') { $body['employee_id'] = $ownId; return; }
            if ($method === 'PUT' && $id !== null) return;                                   // handler: report, or cancel own
            $deny();

        case 'reviews':                         // read-only; the handler shows only their own, non-draft reviews
            if ($method === 'GET') return;
            $deny();

        case 'team':
            if ($method === 'GET' && has_direct_reports($pdo)) return;
            $deny();

        case 'payroll':                         // own payslips and own loans
            if ($method === 'GET' && $sub === '') { $_GET['employee_id'] = $ownId; return; }
            if ($method === 'GET' && $sub === 'loans' && !isset($seg[2])) { $_GET['employee_id'] = $ownId; return; }
            if ($method === 'GET' && $id !== null && ($seg[2] ?? '') === 'link' && hr_owns_row($pdo, 'payroll', $id, $ownId)) return;
            if ($method === 'GET' && $id !== null && hr_owns_row($pdo, 'payroll', $id, $ownId)) return;
            $deny();

        case 'documents':
            if ($method === 'GET' && $sub === 'types') return;
            if ($sub === 'employee' && isset($seg[2]) && ctype_digit($seg[2]) && intval($seg[2]) === $ownId) {
                $action = $seg[3] ?? '';
                if ($method === 'GET' && $action === '') return;
                if ($method === 'POST' && $action === 'upload') return;
            }
            $deny();

        case 'stats':
            if ($method === 'GET' && $sub === 'me') return;
            $deny();

        default:
            $deny();
    }
}
