<?php
// =============================================
// HR Management System — PHP Backend
// Main Router / Entry Point
// =============================================

// ---- CORS Headers ----
// Allow all origins for API access (tighten in production if needed)
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS, PATCH');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, X-App-Id');
header('Access-Control-Max-Age: 86400'); // Cache preflight for 24 hours

// Handle OPTIONS preflight immediately
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// ---- Load core dependencies ----
require_once __DIR__ . '/config/database.php';
require_once __DIR__ . '/helpers/response.php';
require_once __DIR__ . '/helpers/auth.php';
require_once __DIR__ . '/helpers/app_lock.php';
require_once __DIR__ . '/helpers/tenant.php';
require_once __DIR__ . '/helpers/group.php';
require_once __DIR__ . '/helpers/features.php';
require_once __DIR__ . '/helpers/chain.php';
require_once __DIR__ . '/helpers/labor_law.php';
require_once __DIR__ . '/api/decisions.php';
require_once __DIR__ . '/api/complaints.php';
require_once __DIR__ . '/api/coach.php';
require_once __DIR__ . '/api/field.php';
require_once __DIR__ . '/api/career.php';
require_once __DIR__ . '/api/portfolio.php';
require_once __DIR__ . '/api/arabic.php';
require_once __DIR__ . '/helpers/policy.php';

// Timestamps (created_at, read_at...) are always stored in UTC; the apps convert them to the viewer's local time.
try { getDB()->exec("SET time_zone = '+00:00'"); } catch (Throwable $e) { /* the real error surfaces on the first query */ }

// ---- Parse request ----
$method = $_SERVER['REQUEST_METHOD'];

// Parse and clean the path
$requestUri = $_SERVER['REQUEST_URI'];

// Strip query string
$pathOnly = strtok($requestUri, '?');

// Decode URL encoding
$pathOnly = urldecode($pathOnly);

// Normalize slashes
$pathOnly = trim($pathOnly, '/');

// ---- Serve the web portal (React SPA) for browser page loads ----
// Browser navigations (Accept: text/html) to anything outside /api/ get the
// portal's index.html; API calls (with /api/ prefix or JSON Accept) fall through.
if ($method === 'GET'
    && strpos($pathOnly, 'api/') !== 0
    && $pathOnly !== 'api'
    && $pathOnly !== 'health'
    && !in_array(strtok($pathOnly, '/'), ['payslip-view', 'arabic-view'], true)     // printable pages are served by the API, never by the portal
    && strpos($_SERVER['HTTP_ACCEPT'] ?? '', 'text/html') !== false
    && is_file(__DIR__ . '/index.html')) {
    header('Content-Type: text/html; charset=utf-8');
    header('Cache-Control: no-cache, must-revalidate');
    readfile(__DIR__ . '/index.html');
    exit;
}

// Strip common base prefixes: 'api', 'index.php'
// This supports hosting in both root and /api/ subdirectory
$pathOnly = preg_replace('#^api/?#', '', $pathOnly);
$pathOnly = preg_replace('#^index\.php/?#', '', $pathOnly);
$pathOnly = ltrim($pathOnly, '/');

// Parse JSON body for POST/PUT/PATCH requests
$body = [];
$rawInput = file_get_contents('php://input');
if (!empty($rawInput)) {
    $decoded = json_decode($rawInput, true);
    if (json_last_error() === JSON_ERROR_NONE && is_array($decoded)) {
        $body = $decoded;
    }
}

// Merge form data for multipart/form-data requests
if (!empty($_POST)) {
    $body = array_merge($body, $_POST);
}

// The mobile app sends camelCase keys; handlers read snake_case.
$body = hr_snake_keys($body);
$_GET = hr_snake_keys($_GET); // ?employeeId=1 -> employee_id

// ---- Determine primary route segment ----
$segments = explode('/', $pathOnly);
$firstSegment = strtolower($segments[0] ?? '');

// ---- Access control ----
// Public: API info, health check, /auth/* (login etc.) and company sign-up.
// Everything else needs a valid token, is confined to the caller's company, and is
// limited by role: employees -> own records only (helpers/auth.php),
// hr_manager -> modules the admin has not switched off, hr_admin -> everything.
if (!in_array($firstSegment, ['', 'health', 'auth', 'companies', 'payslip-view', 'arabic-view'], true)) {
    $authUser = get_authenticated_user();
    if (!$authUser) {
        error_response('Unauthorized. Please log in.', 401);
    }
    hr_set_user($authUser);
    if (($authUser['company_status'] ?? 'active') !== 'active') {
        error_response('This company account is suspended.', 403);
    }
    try {
        // Working in another company of the group with a read-only grant: look, never change
        if (!empty($authUser['access_read_only']) && $method !== 'GET' && !in_array($firstSegment, ['group', 'notifications'], true)) {
            error_response('You have read-only access to this company.', 403);
        }
        // 'custom' grant: routes that belong to no module (reports, audit, points...) stay closed unless known to be safe
        if (!empty($authUser['is_away']) && ($authUser['access_level'] ?? '') === 'custom'
            && hr_module_for_route($firstSegment) === null && !in_array($firstSegment, GROUP_CUSTOM_SAFE_ROUTES, true)) {
            error_response('Forbidden. This area is not included in your access to this company.', 403);
        }
        // Modules the company admin has switched off are closed for everybody
        $module = hr_module_for_route($firstSegment);
        if ($module !== null && !company_module_enabled(getDB(), $module)) {
            error_response('This module is turned off for your company.', 403);
        }
        // Premium features the owner has not switched on for this company are closed for everybody
        feature_gate(getDB(), $firstSegment);
        $role = $authUser['role'] ?? '';
        if ($role === 'employee') {
            hr_enforce_employee_scope($firstSegment, $segments, $method, $body, (int)($authUser['employee_id'] ?? 0), getDB());
        } elseif ($role === 'hr_manager') {
            $module = hr_module_for_route($firstSegment);
            if ($module !== null && !hr_manager_module_allowed(getDB(), (int)$authUser['id'], $module)) {
                error_response('Forbidden. This module is disabled for your account.', 403);
            }
        }
    } catch (PDOException $e) {
        error_response('A database error occurred. Please try again.', 500);
    }
}

// ---- Route dispatcher ----
try {
    switch (true) {

        // Health check
        case $firstSegment === 'health':
            json_response([
                'status'    => 'ok',
                'timestamp' => date('Y-m-d H:i:s'),
                'version'   => '1.0.0',
            ]);
            break;

        // Printable payslip (signed link, no login header)
        case $firstSegment === 'payslip-view':
            require_once __DIR__ . '/api/payslip_view.php';
            handle_payslip_view();
            break;

        // Auth routes: /auth/login, /auth/me, etc.
        case $firstSegment === 'auth':
            require_once __DIR__ . '/api/auth.php';
            handle_auth($pathOnly, $method, $body);
            break;

        // Employees: /employees, /employees/:id, /employees/me
        case $firstSegment === 'employees':
            require_once __DIR__ . '/api/employees.php';
            handle_employees($pathOnly, $method, $body);
            break;

        // Departments: /departments, /departments/:id
        case $firstSegment === 'departments':
            require_once __DIR__ . '/api/departments.php';
            handle_departments($pathOnly, $method, $body);
            break;

        // Leaves: /leaves, /leaves/:id, /leaves/policy, /leaves/analytics
        case $firstSegment === 'leaves':
            require_once __DIR__ . '/api/leaves.php';
            handle_leaves($pathOnly, $method, $body);
            break;

        // Attendance rules (must come before 'attendance' to avoid prefix conflict)
        case $firstSegment === 'attendance-rules':
            require_once __DIR__ . '/api/attendance_rules.php';
            handle_attendance_rules($pathOnly, $method, $body);
            break;

        // Attendance: /attendance, /attendance/:id
        case $firstSegment === 'attendance':
            require_once __DIR__ . '/api/attendance.php';
            handle_attendance($pathOnly, $method, $body);
            break;

        // Payroll: /payroll, /payroll/:id
        case $firstSegment === 'payroll':
            require_once __DIR__ . '/api/payroll.php';
            handle_payroll($pathOnly, $method, $body);
            break;

        // Recruitment umbrella: /recruitment/jobs, /recruitment/applications
        case $firstSegment === 'recruitment':
            require_once __DIR__ . '/api/recruitment.php';
            handle_recruitment($pathOnly, $method, $body);
            break;

        // Jobs accessed directly: /jobs, /jobs/:id
        case $firstSegment === 'jobs':
            require_once __DIR__ . '/api/recruitment.php';
            // Rewrite path so handle_recruitment sees "jobs/..." properly
            handle_recruitment($pathOnly, $method, $body);
            break;

        // Applications accessed directly: /applications, /applications/:id
        case $firstSegment === 'applications':
            require_once __DIR__ . '/api/recruitment.php';
            handle_recruitment($pathOnly, $method, $body);
            break;

        // Talent pool: /talent-pool/overview, /talent-pool/candidates, /talent-pool/archive
        case $firstSegment === 'talent-pool':
            require_once __DIR__ . '/api/talent_pool.php';
            handle_talent_pool($pathOnly, $method, $body);
            break;

        // Reviews: /reviews, /reviews/:id
        case $firstSegment === 'reviews':
            require_once __DIR__ . '/api/reviews.php';
            handle_reviews($pathOnly, $method, $body);
            break;

        // Announcements: /announcements, /announcements/:id
        case $firstSegment === 'announcements':
            require_once __DIR__ . '/api/announcements.php';
            handle_announcements($pathOnly, $method, $body);
            break;

        // Documents: /documents/types, /documents/:employeeId, /documents/:employeeId/:typeId
        case $firstSegment === 'documents':
            require_once __DIR__ . '/api/documents.php';
            handle_documents($pathOnly, $method, $body);
            break;

        // Shifts: /shifts, /shifts/:id, /shifts/assign
        case $firstSegment === 'shifts':
            require_once __DIR__ . '/api/shifts.php';
            handle_shifts($pathOnly, $method, $body);
            break;

        // HR Staff: /hr-staff, /hr-staff/:id
        case $firstSegment === 'hr-staff':
            require_once __DIR__ . '/api/hr_staff.php';
            handle_hr_staff($pathOnly, $method, $body);
            break;

        // Dashboard stats: /stats
        case $firstSegment === 'stats':
            require_once __DIR__ . '/api/stats.php';
            handle_stats($pathOnly, $method, $body);
            break;

        // Online meetings: schedule, join, audio/video call set-up messages
        case $firstSegment === 'meetings':
            require_once __DIR__ . '/api/meetings.php';
            handle_meetings($pathOnly, $method, $body);
            break;

        // Local labour law packs (Egypt / Saudi): rules, insurance, tax, end of service, Hijri dates
        case $firstSegment === 'labor-law':
            require_once __DIR__ . '/api/labor_law.php';
            handle_labor_law($pathOnly, $method, $body);
            break;

        // Fair decisions: every adverse decision with its reason, and disputes
        case $firstSegment === 'decisions':
            handle_decisions($pathOnly, $method, $body);
            break;

        // Complaints: team head -> HR -> owner
        case $firstSegment === 'complaints':
            handle_complaints($pathOnly, $method, $body);
            break;

        // Manager coach: this week's advice for managers
        case $firstSegment === 'coach':
            handle_coach($pathOnly, $method, $body);
            break;

        // Field work proof: visits with GPS, photo, route and customer signature
        case $firstSegment === 'field':
            handle_field($pathOnly, $method, $body);
            break;

        // Career path: levels, skills, next step, promotion
        case $firstSegment === 'career':
            handle_career($pathOnly, $method, $body);
            break;

        // Printable Arabic letter (signed link, no login header)
        case $firstSegment === 'arabic-view':
            handle_arabic_view();
            break;

        // Real Arabic pack: letters, amounts in words, voice commands
        case $firstSegment === 'arabic':
            handle_arabic($pathOnly, $method, $body);
            break;

        // Owner dashboard: all companies side by side
        case $firstSegment === 'portfolio':
            handle_portfolio($pathOnly, $method, $body);
            break;

        // Owner control panel: which premium features each company may use
        // Leaving certificates (designer, issue, e-mail, planned account closing) and contract alarms
        case $firstSegment === 'certificates':
            require_once __DIR__ . '/api/certificates.php';
            handle_certificates($pathOnly, $method, $body);
            break;

        case $firstSegment === 'contracts':
            require_once __DIR__ . '/api/contracts.php';
            handle_contracts($pathOnly, $method, $body);
            break;

        case $firstSegment === 'owner':
            require_once __DIR__ . '/api/owner.php';
            handle_owner($pathOnly, $method, $body);
            break;

        // Company group: company switcher, companies under the holding, who may enter which company
        case $firstSegment === 'group':
            require_once __DIR__ . '/api/group.php';
            handle_group($pathOnly, $method, $body);
            break;

        // Company sign-up (public) — handled by the auth module
        case $firstSegment === 'companies':
            require_once __DIR__ . '/api/auth.php';
            handle_auth($pathOnly, $method, $body);
            break;

        // Company settings / branding
        case $firstSegment === 'company':
            require_once __DIR__ . '/api/company.php';
            handle_company($pathOnly, $method, $body);
            break;

        case $firstSegment === 'holidays':
            require_once __DIR__ . '/api/holidays.php';
            handle_holidays($pathOnly, $method, $body);
            break;

        case $firstSegment === 'leave-types':
            require_once __DIR__ . '/api/leave_types.php';
            handle_leave_types($pathOnly, $method, $body);
            break;

        case $firstSegment === 'assistant':
            require_once __DIR__ . '/api/assistant.php';
            handle_assistant($pathOnly, $method, $body);
            break;

        case $firstSegment === 'kudos':
            require_once __DIR__ . '/api/kudos.php';
            handle_kudos($pathOnly, $method, $body);
            break;

        case $firstSegment === 'onboarding':
            require_once __DIR__ . '/api/onboarding.php';
            handle_onboarding($pathOnly, $method, $body);
            break;

        case $firstSegment === 'notifications':
            require_once __DIR__ . '/api/notifications.php';
            handle_notifications($pathOnly, $method, $body);
            break;

        case $firstSegment === 'requests':
            require_once __DIR__ . '/api/requests.php';
            handle_requests($pathOnly, $method, $body);
            break;

        case $firstSegment === 'directory':
            require_once __DIR__ . '/api/directory.php';
            handle_directory($pathOnly, $method, $body);
            break;

        case $firstSegment === 'team':
            require_once __DIR__ . '/api/directory.php';
            handle_team($pathOnly, $method, $body);
            break;

        case $firstSegment === 'profile':
            require_once __DIR__ . '/api/profile.php';
            handle_profile($pathOnly, $method, $body);
            break;

        case $firstSegment === 'points':
            require_once __DIR__ . '/api/points.php';
            handle_points($pathOnly, $method, $body);
            break;

        case $firstSegment === 'reports':
            require_once __DIR__ . '/api/reports.php';
            handle_reports($pathOnly, $method, $body);
            break;

        case $firstSegment === 'audit':
            require_once __DIR__ . '/api/reports.php';
            handle_audit($pathOnly, $method, $body);
            break;

        case $firstSegment === 'org':
            require_once __DIR__ . '/api/reports.php';
            handle_org($pathOnly, $method, $body);
            break;

        // Root — show API info
        case $firstSegment === '':
            json_response([
                'name'    => 'HR Management System API',
                'version' => '1.0.0',
                'status'  => 'running',
                'endpoints' => [
                    'GET  /health',
                    'POST /auth/login',
                    'GET  /auth/me',
                    'GET  /employees',
                    'GET  /departments',
                    'GET  /leaves',
                    'GET  /attendance',
                    'GET  /payroll',
                    'GET  /jobs',
                    'GET  /applications',
                    'GET  /talent-pool/overview',
                    'GET  /reviews',
                    'GET  /announcements',
                    'GET  /documents/types',
                    'GET  /shifts',
                    'GET  /hr-staff',
                    'GET  /stats',
                ],
            ]);
            break;

        // 404 fallback
        default:
            error_response('Endpoint not found: ' . $firstSegment, 404);
    }

} catch (PDOException $e) {
    // Database errors
    error_log('[HR API] PDOException: ' . $e->getMessage());
    error_response('A database error occurred. Please try again.', 500);

} catch (Throwable $e) {
    // Catch-all for any unexpected errors
    error_log('[HR API] Exception: ' . $e->getMessage() . ' in ' . $e->getFile() . ':' . $e->getLine());
    error_response('An internal server error occurred.', 500);
}
