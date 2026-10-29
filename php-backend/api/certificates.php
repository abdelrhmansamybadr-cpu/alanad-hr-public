<?php
/**
 * Leaving certificates (HR only, company-scoped)
 *
 *   GET    /certificates/samples                     ready-made designs
 *   GET/POST /certificates/templates                 list / save a design   PUT/DELETE /certificates/templates/:id
 *   POST   /certificates/assets   {dataUrl,name}     upload a background / logo / signature picture
 *   GET    /certificates/assets/:id                  the picture itself (HR only)
 *   POST   /certificates/draft    {employeeId,templateId,kind}   reserve the certificate number
 *   POST   /certificates/:id/issue {imageData,title,width,height,values,sendEmail,emailTo,leaveDate,close}
 *   GET    /certificates[?employeeId=]               issued certificates
 *   GET    /certificates/:id/file?type=pdf|image     download      POST /certificates/:id/resend
 *   GET/POST /certificates/closures                  planned account closings   DELETE /certificates/closures/:id   POST .../:id/close-now
 *
 * The layout of a design is a JSON string (blocks of text with {placeholders} and pictures, a frame, ...) so the
 * key conversion of the API never touches it.
 */
require_once __DIR__ . '/../helpers/policy.php';
require_once __DIR__ . '/../helpers/certificates.php';

function handle_certificates(string $path, string $method, array $body): void {
    require_hr();
    $pdo = getDB();
    $seg = explode('/', $path);
    $sub = $seg[1] ?? '';
    exit_apply_due($pdo);

    if ($sub === 'samples' && $method === 'GET') {
        $out = array_map(function ($t) { $t['layout'] = json_encode($t['layout'], JSON_UNESCAPED_UNICODE); return $t; }, cert_samples());
        json_response(['success' => true, 'data' => $out]);
    }
    if ($sub === 'templates') { certs_templates($seg, $method, $body, $pdo); }
    if ($sub === 'assets')    { certs_assets($seg, $method, $body, $pdo); }
    if ($sub === 'closures')  { certs_closures($seg, $method, $body, $pdo); }
    if ($sub === 'draft' && $method === 'POST') { certs_draft($body, $pdo); }

    if ($sub === '' && $method === 'GET') { certs_list($pdo); }
    if ($sub !== '' && ctype_digit($sub)) {
        $id = (int)$sub;
        $act = $seg[2] ?? '';
        if ($act === '' && $method === 'GET')       certs_get($id, $pdo);
        if ($act === 'issue' && $method === 'POST') certs_issue($id, $body, $pdo);
        if ($act === 'file' && $method === 'GET')   certs_file($id, $pdo);
        if ($act === 'resend' && $method === 'POST') certs_resend($id, $body, $pdo);
        if ($act === '' && $method === 'DELETE')    certs_delete($id, $pdo);
    }
    error_response('Not found', 404);
}

// ------------------------------------------------------------------ templates

function certs_clean_layout($raw): string {
    $data = is_string($raw) ? json_decode($raw, true) : null;
    if (!is_array($data)) error_response('The design is not valid', 422);
    $blocks = is_array($data['blocks'] ?? null) ? array_slice($data['blocks'], 0, 60) : [];
    $clean = [];
    foreach ($blocks as $b) {
        if (!is_array($b)) continue;
        $type = ($b['type'] ?? 'text') === 'image' ? 'image' : 'text';
        $x = max(-20, min(120, (float)($b['x'] ?? 0)));
        $y = max(-20, min(120, (float)($b['y'] ?? 0)));
        $w = max(2, min(150, (float)($b['w'] ?? 30)));
        $item = ['id' => mb_substr((string)($b['id'] ?? ('b' . count($clean))), 0, 24), 'type' => $type, 'x' => $x, 'y' => $y, 'w' => $w];
        if ($type === 'image') {
            $item['asset'] = (int)($b['asset'] ?? 0);
            $item['h'] = max(2, min(150, (float)($b['h'] ?? 10)));
        } else {
            $item += [
                'text'   => mb_substr((string)($b['text'] ?? ''), 0, 2000),
                'size'   => max(0.8, min(30, (float)($b['size'] ?? 3))),
                'color'  => preg_match('/^#[0-9a-fA-F]{6}$/', (string)($b['color'] ?? '')) ? $b['color'] : '#1f2937',
                'align'  => in_array($b['align'] ?? '', ['left', 'center', 'right'], true) ? $b['align'] : 'center',
                'bold'   => !empty($b['bold']),
                'italic' => !empty($b['italic']),
                'font'   => in_array($b['font'] ?? '', ['sans', 'serif', 'mono'], true) ? $b['font'] : 'sans',
                'lh'     => max(1, min(3, (float)($b['lh'] ?? 1.5))),
            ];
        }
        $clean[] = $item;
    }
    $f = is_array($data['frame'] ?? null) ? $data['frame'] : [];
    $frame = [
        'style' => in_array($f['style'] ?? '', ['none', 'single', 'double'], true) ? $f['style'] : 'none',
        'color' => preg_match('/^#[0-9a-fA-F]{6}$/', (string)($f['color'] ?? '')) ? $f['color'] : '#b8975a',
        'width' => max(1, min(40, (float)($f['width'] ?? 6))),
        'inset' => max(0, min(200, (float)($f['inset'] ?? 24))),
    ];
    $json = json_encode(['frame' => $frame, 'blocks' => $clean], JSON_UNESCAPED_UNICODE);
    if (strlen($json) > 200000) error_response('The design is too large', 422);
    return $json;
}

function certs_asset_ok(PDO $pdo, $id): bool {
    if (!$id) return true;
    $s = $pdo->prepare("SELECT 1 FROM certificate_assets WHERE id = ? AND company_id = ?");
    $s->execute([(int)$id, cid()]);
    return (bool)$s->fetchColumn();
}

function certs_template_row(array $t): array {
    $t['url'] = $t['bg_asset_id'] ? '/certificates/assets/' . $t['bg_asset_id'] : null;
    return $t;
}

function certs_templates(array $seg, string $method, array $body, PDO $pdo): void {
    $id = (isset($seg[2]) && ctype_digit($seg[2])) ? (int)$seg[2] : null;
    if ($id === null && $method === 'GET') {
        $s = $pdo->prepare("SELECT * FROM certificate_templates WHERE company_id = ? ORDER BY updated_at DESC, id DESC");
        $s->execute([cid()]);
        json_response(['success' => true, 'data' => array_map('certs_template_row', $s->fetchAll())]);
    }
    if ($id !== null && $method === 'GET') {
        $t = certs_template_fetch($pdo, $id);
        json_response(['success' => true, 'data' => certs_template_row($t)]);
    }
    if ($id !== null && $method === 'DELETE') {
        certs_template_fetch($pdo, $id);
        $pdo->prepare("DELETE FROM certificate_templates WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
        json_response(['success' => true, 'message' => 'Design deleted']);
    }
    if (($id === null && $method === 'POST') || ($id !== null && $method === 'PUT')) {
        $name = trim((string)($body['name'] ?? ''));
        if ($name === '') error_response('Give the design a name', 422);
        $kind = in_array($body['kind'] ?? '', ['experience', 'end_of_service', 'clearance', 'custom'], true) ? $body['kind'] : 'custom';
        $lang = ($body['lang'] ?? 'en') === 'ar' ? 'ar' : 'en';
        $w = max(300, min(4000, (int)($body['width'] ?? 1123)));
        $h = max(300, min(4000, (int)($body['height'] ?? 794)));
        $bgColor = preg_match('/^#[0-9a-fA-F]{6}$/', (string)($body['bg_color'] ?? '')) ? $body['bg_color'] : '#ffffff';
        $bgAsset = !empty($body['bg_asset_id']) ? (int)$body['bg_asset_id'] : null;
        $layout  = certs_clean_layout($body['layout'] ?? '');
        if (!certs_asset_ok($pdo, $bgAsset)) error_response('Background picture not found', 422);
        foreach (json_decode($layout, true)['blocks'] as $b) {
            if ($b['type'] === 'image' && !certs_asset_ok($pdo, $b['asset'])) error_response('A picture in the design was not found', 422);
        }
        if ($id === null) {
            $pdo->prepare("INSERT INTO certificate_templates (company_id, name, kind, lang, width, height, bg_color, bg_asset_id, layout, created_by) VALUES (?,?,?,?,?,?,?,?,?,?)")
                ->execute([cid(), mb_substr($name, 0, 120), $kind, $lang, $w, $h, $bgColor, $bgAsset, $layout, (int)me()['id']]);
            $id = (int)$pdo->lastInsertId();
            audit($pdo, 'create', 'certificate_template', $id, ['name' => $name]);
            json_response(['success' => true, 'data' => certs_template_row(certs_template_fetch($pdo, $id))], 201);
        }
        certs_template_fetch($pdo, $id);
        $pdo->prepare("UPDATE certificate_templates SET name=?, kind=?, lang=?, width=?, height=?, bg_color=?, bg_asset_id=?, layout=? WHERE id=? AND company_id=?")
            ->execute([mb_substr($name, 0, 120), $kind, $lang, $w, $h, $bgColor, $bgAsset, $layout, $id, cid()]);
        audit($pdo, 'update', 'certificate_template', $id, ['name' => $name]);
        json_response(['success' => true, 'data' => certs_template_row(certs_template_fetch($pdo, $id))]);
    }
    error_response('Method not allowed', 405);
}

function certs_template_fetch(PDO $pdo, int $id): array {
    $s = $pdo->prepare("SELECT * FROM certificate_templates WHERE id = ? AND company_id = ?");
    $s->execute([$id, cid()]);
    $t = $s->fetch();
    if (!$t) error_response('Design not found', 404);
    return $t;
}

// ------------------------------------------------------------------ pictures

function certs_assets(array $seg, string $method, array $body, PDO $pdo): void {
    $id = (isset($seg[2]) && ctype_digit($seg[2])) ? (int)$seg[2] : null;
    if ($id === null && $method === 'POST') {
        $img = cert_decode_image($body['data_url'] ?? null);
        if (!$img) error_response('Use a PNG, JPG or WEBP picture up to 8 MB', 422);
        [$bytes, $mime, $w, $h] = $img;
        $ext = ['image/png' => 'png', 'image/jpeg' => 'jpg', 'image/webp' => 'webp'][$mime];
        $path = cert_store($bytes, $ext);
        $pdo->prepare("INSERT INTO certificate_assets (company_id, name, file_path, mime_type, width, height) VALUES (?,?,?,?,?,?)")
            ->execute([cid(), mb_substr(trim((string)($body['name'] ?? '')), 0, 160), $path, $mime, $w, $h]);
        $newId = (int)$pdo->lastInsertId();
        json_response(['success' => true, 'data' => ['id' => $newId, 'url' => "/certificates/assets/$newId", 'width' => $w, 'height' => $h]], 201);
    }
    if ($id !== null && $method === 'GET') {
        $s = $pdo->prepare("SELECT * FROM certificate_assets WHERE id = ? AND company_id = ?");
        $s->execute([$id, cid()]);
        $a = $s->fetch();
        if (!$a) error_response('Picture not found', 404);
        cert_stream($a['file_path'], $a['mime_type'], 'picture-' . $id . '.' . (['image/png' => 'png', 'image/jpeg' => 'jpg', 'image/webp' => 'webp'][$a['mime_type']] ?? 'bin'));
    }
    error_response('Method not allowed', 405);
}

// ------------------------------------------------------------------ certificates

function certs_employee(PDO $pdo, int $id): array {
    $s = $pdo->prepare("SELECT e.id, e.first_name, e.last_name, e.email, e.status, e.position, d.name AS department_name FROM employees e LEFT JOIN departments d ON d.id = e.department_id WHERE e.id = ? AND e.company_id = ?");
    $s->execute([$id, cid()]);
    $e = $s->fetch();
    if (!$e) error_response('Employee not found', 404);
    return $e;
}

function certs_row(array $c): array {
    unset($c['image_path'], $c['pdf_path']);
    $c['has_file'] = $c['status'] === 'issued';
    return $c;
}

function certs_draft(array $body, PDO $pdo): void {
    $emp = certs_employee($pdo, (int)($body['employee_id'] ?? 0));
    $tpl = !empty($body['template_id']) ? certs_template_fetch($pdo, (int)$body['template_id']) : null;
    $kind = $tpl['kind'] ?? (in_array($body['kind'] ?? '', ['experience', 'end_of_service', 'clearance', 'custom'], true) ? $body['kind'] : 'custom');
    cert_cleanup_drafts($pdo);
    $d = cert_create_draft($pdo, (int)$emp['id'], $tpl ? (int)$tpl['id'] : null, $kind, (int)att_now($pdo)->format('Y'));
    $company = company_get($pdo, cid());
    json_response(['success' => true, 'data' => [
        'id' => $d['id'], 'serial' => $d['serial'], 'issue_date' => att_now($pdo)->format('Y-m-d'),
        'company' => (string)($company['name'] ?? ''), 'employee' => $emp,
    ]], 201);
}

function certs_fetch(PDO $pdo, int $id): array {
    $s = $pdo->prepare("SELECT * FROM certificates WHERE id = ? AND company_id = ?");
    $s->execute([$id, cid()]);
    $c = $s->fetch();
    if (!$c) error_response('Certificate not found', 404);
    return $c;
}

function certs_get(int $id, PDO $pdo): void {
    json_response(['success' => true, 'data' => certs_row(certs_fetch($pdo, $id))]);
}

function certs_list(PDO $pdo): void {
    $where = ["c.company_id = ?", "c.status = 'issued'"]; $args = [cid()];
    if (!empty($_GET['employee_id'])) { $where[] = 'c.employee_id = ?'; $args[] = (int)$_GET['employee_id']; }
    $s = $pdo->prepare("SELECT c.id, c.employee_id, c.serial, c.kind, c.title, c.status, c.leave_date, c.emailed_to, c.emailed_at, c.issued_at, c.template_id,
                               CONCAT(e.first_name, ' ', e.last_name) AS employee_name, e.status AS employee_status
                        FROM certificates c JOIN employees e ON e.id = c.employee_id
                        WHERE " . implode(' AND ', $where) . " ORDER BY c.issued_at DESC, c.id DESC LIMIT 300");
    $s->execute($args);
    json_response(['success' => true, 'data' => $s->fetchAll()]);
}

function certs_delete(int $id, PDO $pdo): void {
    $c = certs_fetch($pdo, $id);
    if ($c['status'] !== 'draft') error_response('An issued certificate is kept as a record', 409);
    $pdo->prepare("DELETE FROM certificates WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
    json_response(['success' => true, 'message' => 'Draft removed']);
}

function certs_file(int $id, PDO $pdo): void {
    $c = certs_fetch($pdo, $id);
    if ($c['status'] !== 'issued') error_response('Not issued yet', 404);
    $pdfWanted = (($_GET['type'] ?? 'pdf') !== 'image');
    $path = $pdfWanted ? $c['pdf_path'] : $c['image_path'];
    if (!$path) error_response('File not found', 404);
    cert_stream($path, $pdfWanted ? 'application/pdf' : 'image/jpeg', $c['serial'] . ($pdfWanted ? '.pdf' : '.jpg'), !empty($_GET['download']));
}

function certs_mail(PDO $pdo, array $c, array $emp, string $to): bool {
    require_once __DIR__ . '/../helpers/mailer.php';
    $company = (string)(company_get($pdo, cid())['name'] ?? 'Al Anad HR');
    $name = trim($emp['first_name'] . ' ' . $emp['last_name']);
    $title = $c['title'] !== '' ? $c['title'] : 'Certificate';
    $html = mail_template(
        $company, $title, 'شهادتك من ' . $company,
        "Dear {$name}, your certificate ({$c['serial']}) from {$company} is attached to this message as a PDF and as a picture. Please keep it safe.",
        "عزيزي/عزيزتي {$name}، مرفقة شهادتك رقم ({$c['serial']}) الصادرة من {$company} بصيغة PDF وصورة. يرجى الاحتفاظ بها."
    );
    $atts = [];
    foreach ([['pdf_path', 'application/pdf', '.pdf'], ['image_path', 'image/jpeg', '.jpg']] as [$col, $mime, $ext]) {
        $full = $c[$col] ? realpath(__DIR__ . '/../' . $c[$col]) : false;
        if ($full && is_file($full)) $atts[] = ['name' => $c['serial'] . $ext, 'mime' => $mime, 'data' => file_get_contents($full)];
    }
    return mail_send_attach($to, "$company: $title", $html, $atts, $company);
}

function certs_issue(int $id, array $body, PDO $pdo): void {
    $c = certs_fetch($pdo, $id);
    if ($c['status'] !== 'draft') error_response('This certificate was already issued', 409);
    $emp = certs_employee($pdo, (int)$c['employee_id']);

    $img = cert_decode_image($body['image_data'] ?? null);
    if (!$img) error_response('The certificate picture is missing or not a PNG/JPG', 422);
    [$bytes, $mime, $pxW, $pxH] = $img;
    $jpeg = cert_to_jpeg($bytes, $mime);
    if ($jpeg === null) error_response('Send the certificate as a JPG picture', 422);
    $info = @getimagesizefromstring($jpeg);
    if ($info) { $pxW = (int)$info[0]; $pxH = (int)$info[1]; }

    $w = max(300, min(4000, (int)($body['width'] ?? 1123)));
    $h = max(300, min(4000, (int)($body['height'] ?? round($w * $pxH / max(1, $pxW)))));
    $leave = null;
    if (!empty($body['leave_date'])) {
        $d = DateTime::createFromFormat('Y-m-d', (string)$body['leave_date']);
        if (!$d || $d->format('Y-m-d') !== $body['leave_date']) error_response('Leaving date must be YYYY-MM-DD', 422);
        $leave = $d->format('Y-m-d');
    }
    $plan = is_array($body['close'] ?? null) ? $body['close'] : ['mode' => 'none'];
    exit_close_time($pdo, $plan);                                  // validates before anything is saved

    $imgPath = cert_store($jpeg, 'jpg');
    $pdfPath = cert_store(cert_pdf($jpeg, $pxW, $pxH, $w * 0.75, $h * 0.75), 'pdf');
    $title = mb_substr(trim((string)($body['title'] ?? '')), 0, 160);
    $values = isset($body['values']) ? mb_substr(is_string($body['values']) ? $body['values'] : json_encode($body['values'], JSON_UNESCAPED_UNICODE), 0, 5000) : null;
    $pdo->prepare("UPDATE certificates SET status='issued', title=?, width=?, height=?, image_path=?, pdf_path=?, leave_date=?, data_json=?, issued_by=?, issued_at=? WHERE id=? AND company_id=?")
        ->execute([$title, $w, $h, $imgPath, $pdfPath, $leave, $values, (int)me()['id'], att_now($pdo)->format('Y-m-d H:i:s'), $id, cid()]);
    $c = certs_fetch($pdo, $id);
    audit($pdo, 'issue', 'certificate', $id, ['serial' => $c['serial'], 'employee_id' => (int)$emp['id']]);

    $emailed = null;
    if (!empty($body['send_email'])) {
        $to = trim((string)($body['email_to'] ?? '')) ?: (string)$emp['email'];
        if (!filter_var($to, FILTER_VALIDATE_EMAIL)) error_response('The e-mail address is not valid', 422);
        $emailed = certs_mail($pdo, $c, $emp, $to);
        if ($emailed) $pdo->prepare("UPDATE certificates SET emailed_to = ?, emailed_at = ? WHERE id = ?")->execute([$to, att_now($pdo)->format('Y-m-d H:i:s'), $id]);
    }

    $closure = exit_schedule($pdo, (int)$emp['id'], $id, $plan, $leave, 'Left the company (certificate ' . $c['serial'] . ')');
    $who = trim($emp['first_name'] . ' ' . $emp['last_name']);
    if (!$closure && $emp['status'] !== 'inactive') {
        notify_hr($pdo, 'exit_open', 'Close the account?', "$who received a certificate but the account is still open. Close it when the time comes.", ['employee_id' => (int)$emp['id'], 'certificate_id' => $id]);
    }
    json_response(['success' => true, 'data' => ['certificate' => certs_row(certs_fetch($pdo, $id)), 'emailed' => $emailed, 'closure' => $closure]], 201);
}

function certs_resend(int $id, array $body, PDO $pdo): void {
    $c = certs_fetch($pdo, $id);
    if ($c['status'] !== 'issued') error_response('Not issued yet', 409);
    $emp = certs_employee($pdo, (int)$c['employee_id']);
    $to = trim((string)($body['email_to'] ?? '')) ?: (string)$emp['email'];
    if (!filter_var($to, FILTER_VALIDATE_EMAIL)) error_response('The e-mail address is not valid', 422);
    $ok = certs_mail($pdo, $c, $emp, $to);
    if ($ok) $pdo->prepare("UPDATE certificates SET emailed_to = ?, emailed_at = ? WHERE id = ?")->execute([$to, att_now($pdo)->format('Y-m-d H:i:s'), $id]);
    json_response(['success' => true, 'data' => ['emailed' => $ok, 'to' => $to]]);
}

// ------------------------------------------------------------------ planned account closings

function certs_closures(array $seg, string $method, array $body, PDO $pdo): void {
    $id  = (isset($seg[2]) && ctype_digit($seg[2])) ? (int)$seg[2] : null;
    $act = $seg[3] ?? '';
    if ($id === null && $method === 'GET') {
        $s = $pdo->prepare("SELECT x.id, x.employee_id, x.certificate_id, x.close_at, x.status, x.leave_date, x.done_at, CONCAT(e.first_name, ' ', e.last_name) AS employee_name
                            FROM exit_closures x JOIN employees e ON e.id = x.employee_id
                            WHERE x.company_id = ? AND x.status IN ('pending','done') ORDER BY (x.status = 'pending') DESC, x.close_at DESC LIMIT 100");
        $s->execute([cid()]);
        json_response(['success' => true, 'data' => $s->fetchAll()]);
    }
    if ($id === null && $method === 'POST') {
        $emp = certs_employee($pdo, (int)($body['employee_id'] ?? 0));
        if ((int)$emp['id'] === own_employee_id()) error_response('You cannot close your own account', 422);
        $leave = !empty($body['leave_date']) ? (string)$body['leave_date'] : null;
        if ($leave !== null) { $d = DateTime::createFromFormat('Y-m-d', $leave); if (!$d || $d->format('Y-m-d') !== $leave) error_response('Leaving date must be YYYY-MM-DD', 422); }
        $closure = exit_schedule($pdo, (int)$emp['id'], !empty($body['certificate_id']) ? (int)$body['certificate_id'] : null, $body, $leave, 'Left the company');
        audit($pdo, 'schedule_close', 'employee', (int)$emp['id'], $body);
        json_response(['success' => true, 'data' => ['closure' => $closure]], 201);
    }
    if ($id !== null && $method === 'DELETE') {
        $u = $pdo->prepare("UPDATE exit_closures SET status = 'cancelled' WHERE id = ? AND company_id = ? AND status = 'pending'");
        $u->execute([$id, cid()]);
        if ($u->rowCount() !== 1) error_response('No planned closing found', 404);
        json_response(['success' => true, 'message' => 'Closing cancelled']);
    }
    if ($id !== null && $act === 'close-now' && $method === 'POST') {
        $u = $pdo->prepare("UPDATE exit_closures SET close_at = ? WHERE id = ? AND company_id = ? AND status = 'pending'");
        $u->execute([att_now($pdo)->format('Y-m-d H:i:s'), $id, cid()]);
        if ($u->rowCount() !== 1) error_response('No planned closing found', 404);
        exit_apply_due($pdo);
        json_response(['success' => true, 'message' => 'Account closed']);
    }
    error_response('Method not allowed', 405);
}
