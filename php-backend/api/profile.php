<?php
/**
 * Self-service profile (the caller's own data)
 *
 *   GET  /profile                user + employee record + manager + department
 *   PUT  /profile                employees: avatar only (HR data changes go through requests); HR: name, phone, title, avatar
 *   POST /profile/avatar         upload a profile photo (multipart field "file")
 */
function handle_profile(string $path, string $method, array $body): void {
    $pdo = getDB();
    $sub = explode('/', $path)[1] ?? '';

    if ($sub === 'avatar') {
        if ($method !== 'POST') error_response('Method not allowed', 405);
        profile_upload_avatar($pdo);
    }
    switch ($method) {
        case 'GET': profile_show($pdo); break;
        case 'PUT': profile_update($body, $pdo); break;
        default:    error_response('Method not allowed', 405);
    }
}

function profile_show(PDO $pdo): void {
    $user = me();
    $emp  = null;
    if (!empty($user['employee_id'])) {
        $s = $pdo->prepare(
            "SELECT e.*, d.name AS department_name, s.name AS shift_name, s.start_time AS shift_start, s.end_time AS shift_end,
                    CONCAT(m.first_name, ' ', m.last_name) AS manager_name
             FROM employees e
             LEFT JOIN departments d ON d.id = e.department_id
             LEFT JOIN shifts s ON s.id = e.shift_id
             LEFT JOIN employees m ON m.id = e.manager_id
             WHERE e.id = ? AND e.company_id = ?"
        );
        $s->execute([$user['employee_id'], cid()]);
        $emp = $s->fetch() ?: null;
        if ($emp) unset($emp['salary']);          // salary is only shown on payslips
    }
    json_response(['success' => true, 'data' => [
        'user'     => ['id' => (int)$user['id'], 'name' => $user['name'], 'email' => $user['email'], 'role' => $user['role'],
                       'title' => $user['title'], 'phone' => $user['phone'], 'avatar' => $user['avatar']],
        'employee' => $emp,
    ]]);
}

function profile_update(array $body, PDO $pdo): void {
    $user = me();

    // Employees cannot edit anything HR entered (name, phone, address, birth date, ...): they send a
    // change request (POST /requests, type profile_change). Their own photo is the only thing they set.
    if (!empty($user['employee_id'])) {
        $locked = array_diff(array_keys($body), ['avatar']);
        if ($locked) {
            error_response('Your information is managed by HR. Send a change request instead.', 403);
        }
        if (!array_key_exists('avatar', $body)) error_response('No fields to update');
        $pdo->prepare("UPDATE users SET avatar = ? WHERE id = ?")->execute([$body['avatar'] === '' ? null : $body['avatar'], $user['id']]);
        $pdo->prepare("UPDATE employees SET avatar = ? WHERE id = ? AND company_id = ?")->execute([$body['avatar'] === '' ? null : $body['avatar'], $user['employee_id'], cid()]);
        $GLOBALS['HR_USER'] = array_merge($user, ['avatar' => $body['avatar'] ?: null]);
        profile_show($pdo);
        return;
    }

    // HR / admin accounts edit their own user record
    $fields = []; $params = [];
    foreach (['name', 'phone', 'title', 'avatar'] as $f) {
        if (array_key_exists($f, $body)) {
            if ($f === 'name' && trim((string)$body[$f]) === '') error_response('Name cannot be empty', 422);
            $fields[] = "$f = ?";
            $params[] = $body[$f] === '' ? null : trim((string)$body[$f]);
        }
    }
    if (!$fields) error_response('No fields to update');
    $params[] = $user['id'];
    $pdo->prepare("UPDATE users SET " . implode(', ', $fields) . " WHERE id = ?")->execute($params);
    $s = $pdo->prepare("SELECT * FROM users WHERE id = ?");
    $s->execute([$user['id']]);
    $GLOBALS['HR_USER'] = array_merge($user, $s->fetch() ?: []);
    profile_show($pdo);
}

function profile_upload_avatar(PDO $pdo): void {
    $user = me();
    if (!isset($_FILES['file']) || $_FILES['file']['error'] !== UPLOAD_ERR_OK) error_response('No file uploaded');
    $file = $_FILES['file'];
    if ($file['size'] > 5 * 1024 * 1024) error_response('Photo must be 5MB or smaller');
    $mime = (new finfo(FILEINFO_MIME_TYPE))->file($file['tmp_name']);
    $ext  = ['image/png' => 'png', 'image/jpeg' => 'jpg', 'image/webp' => 'webp'][$mime] ?? null;
    if (!$ext) error_response('Photo must be a PNG, JPG or WebP image');

    $dir = __DIR__ . '/../uploads/avatars/';
    if (!is_dir($dir)) mkdir($dir, 0755, true);
    $name = cid() . '-' . (int)$user['id'] . '-' . bin2hex(random_bytes(6)) . '.' . $ext;
    if (!move_uploaded_file($file['tmp_name'], $dir . $name)) error_response('Failed to save the photo', 500);
    $url = '/uploads/avatars/' . $name;

    $pdo->prepare("UPDATE users SET avatar = ? WHERE id = ?")->execute([$url, $user['id']]);
    if (!empty($user['employee_id'])) {
        $pdo->prepare("UPDATE employees SET avatar = ? WHERE id = ? AND company_id = ?")->execute([$url, $user['employee_id'], cid()]);
    }
    json_response(['success' => true, 'data' => ['avatar' => $url]]);
}
