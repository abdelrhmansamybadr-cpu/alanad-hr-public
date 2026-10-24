<?php
/**
 * Company settings / branding (company-scoped)
 *
 *   GET  /company          branding + settings (every signed-in user)
 *   PUT  /company          update settings (admin)
 *   POST /company/logo     upload the company logo (admin), multipart field "file"
 *
 * The mobile app and the web admin panel apply these at start-up, so an admin can
 * change the colours, logo and the enabled modules and every user sees it.
 */
function handle_company(string $path, string $method, array $body): void {
    $pdo = getDB();
    $sub = explode('/', $path)[1] ?? '';

    if ($sub === 'logo') {
        if ($method !== 'POST') error_response('Method not allowed', 405);
        require_admin();
        company_upload_logo($pdo);
        return;
    }

    if ($sub === 'test-email') {
        if ($method !== 'POST') error_response('Method not allowed', 405);
        require_admin();
        $me = me();
        require_once __DIR__ . '/../helpers/mailer.php';
        $name = (string)(company_get($pdo, cid())['name'] ?? 'Al Anad HR');
        $html = mail_template($name, 'Test message', 'رسالة تجريبية', 'E-mail from Al Anad HR is working. You can now send invitations and password codes by e-mail.', 'البريد الإلكتروني من Al Anad HR يعمل. يمكنك الآن إرسال الدعوات ورموز كلمة المرور بالبريد.');
        $ok = mail_send((string)$me['email'], "$name: test message", $html, $name);
        json_response(['success' => true, 'data' => ['emailed' => $ok, 'to' => $me['email']]]);
    }

    switch ($method) {
        case 'GET': company_show($pdo); break;
        case 'PUT': require_admin(); company_update($body, $pdo); break;
        default:    error_response('Method not allowed', 405);
    }
}

/** Modules an admin may switch on/off. */
function company_allowed_modules(): array {
    return ['employees', 'departments', 'leaves', 'attendance', 'shifts', 'payroll', 'recruitment',
            'talent_pool', 'reviews', 'announcements', 'documents', 'requests'];
}

function company_show(PDO $pdo): void {
    $c = company_get($pdo, cid());
    if (!$c) error_response('Company not found', 404);
    json_response(['success' => true, 'data' => company_public($c)]);
}

function company_update(array $body, PDO $pdo): void {
    $fields = [];
    $params = [];

    if (array_key_exists('name', $body)) {
        $name = trim((string)$body['name']);
        if ($name === '' || mb_strlen($name) > 120) error_response('Invalid company name', 422);
        $fields[] = 'name = ?'; $params[] = $name;
    }
    foreach (['primary_color', 'accent_color'] as $f) {
        if (array_key_exists($f, $body)) {
            if (!preg_match('/^#[0-9A-Fa-f]{6}$/', (string)$body[$f])) error_response("$f must look like #00617A", 422);
            $fields[] = "$f = ?"; $params[] = strtoupper($body[$f]);
        }
    }
    if (array_key_exists('timezone', $body)) {
        if (!in_array($body['timezone'], timezone_identifiers_list(), true)) error_response('Unknown time zone', 422);
        $fields[] = 'timezone = ?'; $params[] = $body['timezone'];
    }
    if (array_key_exists('currency', $body)) {
        $cur = strtoupper((string)$body['currency']);
        if (!preg_match('/^[A-Z]{3}$/', $cur)) error_response('Currency must be a 3-letter code', 422);
        $fields[] = 'currency = ?'; $params[] = $cur;
    }
    if (array_key_exists('weekend_days', $body)) {
        $days = is_array($body['weekend_days']) ? $body['weekend_days'] : explode(',', (string)$body['weekend_days']);
        $days = array_values(array_unique(array_map(fn($d) => strtolower(trim($d)), $days)));
        foreach ($days as $d) {
            if (!in_array($d, ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'], true)) error_response('Invalid weekend day', 422);
        }
        $fields[] = 'weekend_days = ?'; $params[] = implode(',', $days);
    }
    if (array_key_exists('language', $body)) {
        if (!in_array($body['language'], ['en', 'ar'], true)) error_response('Language must be en or ar', 422);
        $fields[] = 'language = ?'; $params[] = $body['language'];
    }
    if (array_key_exists('late_grace_minutes', $body)) {
        $g = intval($body['late_grace_minutes']);
        if ($g < 0 || $g > 240) error_response('Grace period must be between 0 and 240 minutes', 422);
        $fields[] = 'late_grace_minutes = ?'; $params[] = $g;
    }
    if (array_key_exists('modules', $body)) {
        if ($body['modules'] === null) {
            $fields[] = 'modules = NULL';
        } else {
            $mods = array_values(array_intersect(company_allowed_modules(), (array)$body['modules']));
            $fields[] = 'modules = ?'; $params[] = json_encode($mods);
        }
    }

    foreach (['attendance_policy', 'points_config', 'payroll_policy'] as $pol) {
        if (array_key_exists($pol, $body) && is_array($body[$pol])) {
            $cur = policy_load($pdo, $pol, $pol === 'attendance_policy' ? att_policy_defaults() : ($pol === 'points_config' ? points_config_defaults() : payroll_policy_defaults()));
            $fields[] = "$pol = ?"; $params[] = json_encode(policy_clean($pol, $body[$pol], $cur));
        }
    }

    if (empty($fields)) error_response('No fields to update');
    $params[] = cid();
    $pdo->prepare("UPDATE companies SET " . implode(', ', $fields) . " WHERE id = ?")->execute($params);
    $GLOBALS['HR_POLICY_CACHE'] = [];
    audit($pdo, 'update', 'company', cid(), array_keys($body));
    company_show($pdo);
}

function company_upload_logo(PDO $pdo): void {
    if (!isset($_FILES['file']) || $_FILES['file']['error'] !== UPLOAD_ERR_OK) error_response('No file uploaded');
    $file = $_FILES['file'];
    if ($file['size'] > 2 * 1024 * 1024) error_response('Logo must be 2MB or smaller');

    $mime = (new finfo(FILEINFO_MIME_TYPE))->file($file['tmp_name']);
    $ext  = ['image/png' => 'png', 'image/jpeg' => 'jpg', 'image/webp' => 'webp'][$mime] ?? null;
    if (!$ext) error_response('Logo must be a PNG, JPG or WebP image');

    $dir = __DIR__ . '/../uploads/logos/';
    if (!is_dir($dir)) mkdir($dir, 0755, true);
    $name = cid() . '-' . bin2hex(random_bytes(6)) . '.' . $ext;
    if (!move_uploaded_file($file['tmp_name'], $dir . $name)) error_response('Failed to save the logo', 500);

    $pdo->prepare("UPDATE companies SET logo_url = ? WHERE id = ?")->execute(['/uploads/logos/' . $name, cid()]);
    company_show($pdo);
}
