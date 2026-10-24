<?php
/**
 * Field work proof (feature `field_proof`): a visit has a customer, a GPS start and end, a photo, the route walked and
 * the customer's signature. Photos and signatures are stored in uploads/field/ (closed to the web server) and streamed
 * only after an access check: the employee, their manager and HR.
 *
 *   POST /field/visits                  {customer_name, lat, lng, customer_phone?, address?, purpose?, photo_base64?}   start (employee)
 *   POST /field/visits/{id}/points      {points: [{lat, lng, t?}]}                                                       route points (owner)
 *   POST /field/visits/{id}/finish      {lat, lng, signature_base64?, signed_name?, notes?, photo_base64?}              finish (owner)
 *   POST /field/visits/{id}/cancel                                                                                       cancel (owner)
 *   GET  /field/visits[?date=&employee_id=&status=]    employee: own; manager: team; HR: all
 *   GET  /field/visits/{id}             details with the route
 *   GET  /field/summary[?from=&to=]     per employee: visits, km, minutes in the field (manager / HR)
 *   GET  /field/file/{id}/{photo|signature}
 */
const FIELD_MAX_PHOTO = 4000000;      // bytes after decoding
const FIELD_MAX_SIGNATURE = 400000;

function handle_field(string $path, string $method, array $body): void {
    $pdo = getDB();
    $seg = explode('/', $path);
    $a = $seg[1] ?? '';
    if ($a === 'summary') { if ($method !== 'GET') error_response('Method not allowed', 405); field_summary($pdo); }
    if ($a === 'file' && ctype_digit((string)($seg[2] ?? '')) && in_array($seg[3] ?? '', ['photo', 'signature'], true)) {
        if ($method !== 'GET') error_response('Method not allowed', 405);
        field_stream($pdo, (int)$seg[2], $seg[3]);
    }
    if ($a !== 'visits') error_response('Endpoint not found: field/' . $a, 404);
    $id = ctype_digit((string)($seg[2] ?? '')) ? (int)$seg[2] : null;
    $act = $seg[3] ?? '';
    if ($id === null) {
        if ($method === 'GET') field_list($pdo);
        if ($method === 'POST') field_start($pdo, $body);
        error_response('Method not allowed', 405);
    }
    if ($act === '' && $method === 'GET') field_one($pdo, $id);
    if ($act === 'points' && $method === 'POST') field_points($pdo, $id, $body);
    if ($act === 'finish' && $method === 'POST') field_finish($pdo, $id, $body);
    if ($act === 'cancel' && $method === 'POST') field_cancel($pdo, $id);
    error_response('Method not allowed', 405);
}

// ------------------------------------------------------------------ helpers

function field_coord($v, float $max): ?float {
    if (!is_numeric($v)) return null;
    $f = (float)$v;
    return abs($f) <= $max ? round($f, 7) : null;
}

function field_km(float $lat1, float $lng1, float $lat2, float $lng2): float {
    $r = 6371000.0;
    $p1 = deg2rad($lat1); $p2 = deg2rad($lat2);
    $dp = $p2 - $p1; $dl = deg2rad($lng2 - $lng1);
    $a = sin($dp / 2) ** 2 + cos($p1) * cos($p2) * sin($dl / 2) ** 2;
    return $r * 2 * atan2(sqrt($a), sqrt(1 - $a));      // metres (name kept short on purpose)
}

/** Decode a base64 image (optionally a data: URL). Returns [bytes, ext] or an error string. */
function field_decode_image(string $b64, int $maxBytes, array $allowedMime) {
    if (preg_match('#^data:[^;]+;base64,#', $b64)) $b64 = preg_replace('#^data:[^;]+;base64,#', '', $b64);
    $raw = base64_decode($b64, true);
    if ($raw === false || $raw === '') return 'The picture could not be read.';
    if (strlen($raw) > $maxBytes) return 'The picture is too large.';
    $mime = (new finfo(FILEINFO_MIME_TYPE))->buffer($raw);
    if (!isset($allowedMime[$mime])) return 'Only ' . implode(' or ', array_values($allowedMime)) . ' pictures are accepted.';
    return [$raw, $allowedMime[$mime]];
}

function field_save(string $raw, string $ext): string {
    $dir = __DIR__ . '/../uploads/field/' . cid() . '/';
    if (!is_dir($dir)) @mkdir($dir, 0755, true);
    $htaccess = __DIR__ . '/../uploads/field/.htaccess';
    if (!is_file($htaccess)) @file_put_contents($htaccess, "Require all denied\n");
    $name = bin2hex(random_bytes(16)) . '.' . $ext;
    if (file_put_contents($dir . $name, $raw) === false) error_response('Failed to save the picture', 500);
    return $name;
}

/** A visit of this company that the caller may see (owner, their manager, HR). */
function field_get(PDO $pdo, int $id): array {
    $s = $pdo->prepare("SELECT v.*, CONCAT(e.first_name, ' ', e.last_name) AS employee_name, e.manager_id
                        FROM field_visits v JOIN employees e ON e.id = v.employee_id WHERE v.id = ? AND v.company_id = ?");
    $s->execute([$id, cid()]);
    $v = $s->fetch();
    if (!$v) error_response('Visit not found', 404);
    $own = (int)$v['employee_id'] === own_employee_id();
    if (!$own && !is_hr() && !is_manager_of($pdo, (int)$v['employee_id'])) error_response('Visit not found', 404);
    return $v;
}

function field_view(array $v): array {
    $end = $v['ended_at'] ?: gmdate('Y-m-d H:i:s');
    $mins = max(0, (int)round((strtotime($end . ' UTC') - strtotime($v['started_at'] . ' UTC')) / 60));
    $flags = [];
    if ($v['status'] === 'done') {
        if (!$v['photo_file']) $flags[] = 'no_photo';
        if (!$v['signature_file']) $flags[] = 'no_signature';
        if ($mins < 2) $flags[] = 'very_short';
        if ($v['distance_m'] < 20 && $mins > 15) $flags[] = 'did_not_move';
    }
    return ['id' => (int)$v['id'], 'employee_id' => (int)$v['employee_id'], 'employee_name' => $v['employee_name'] ?? null,
        'customer_name' => $v['customer_name'], 'customer_phone' => $v['customer_phone'], 'address' => $v['address'], 'purpose' => $v['purpose'],
        'status' => $v['status'], 'started_at' => $v['started_at'], 'ended_at' => $v['ended_at'], 'minutes' => $mins,
        'start_lat' => $v['start_lat'] !== null ? (float)$v['start_lat'] : null, 'start_lng' => $v['start_lng'] !== null ? (float)$v['start_lng'] : null,
        'end_lat' => $v['end_lat'] !== null ? (float)$v['end_lat'] : null, 'end_lng' => $v['end_lng'] !== null ? (float)$v['end_lng'] : null,
        'distance_m' => (int)$v['distance_m'], 'has_photo' => (bool)$v['photo_file'], 'has_signature' => (bool)$v['signature_file'],
        'signed_name' => $v['signed_name'], 'notes' => $v['notes'], 'flags' => $flags];
}

function field_require_owner_active(PDO $pdo, int $id): array {
    $v = field_get($pdo, $id);
    if ((int)$v['employee_id'] !== own_employee_id()) error_response('Only the person who made the visit can do this.', 403);
    if ($v['status'] !== 'active') error_response('This visit is already closed.', 409);
    return $v;
}

// ------------------------------------------------------------------ actions

function field_start(PDO $pdo, array $b): void {
    $eid = own_employee_id();
    if ($eid <= 0) error_response('No employee record linked to this account', 403);
    $name = trim((string)($b['customer_name'] ?? ''));
    if ($name === '' || mb_strlen($name) > 150) error_response('Customer name is required', 422);
    $lat = field_coord($b['lat'] ?? null, 90); $lng = field_coord($b['lng'] ?? null, 180);
    if ($lat === null || $lng === null) error_response('Your location is required to start a visit', 422);
    $open = $pdo->prepare("SELECT id FROM field_visits WHERE company_id = ? AND employee_id = ? AND status = 'active' LIMIT 1");
    $open->execute([cid(), $eid]);
    if ($oid = $open->fetchColumn()) { http_response_code(409); header('Content-Type: application/json'); echo json_encode(['error' => 'You already have a visit in progress. Finish it first.', 'activeVisitId' => (int)$oid]); exit; }
    $photo = null;
    if (!empty($b['photo_base64'])) {
        $img = field_decode_image((string)$b['photo_base64'], FIELD_MAX_PHOTO, ['image/jpeg' => 'jpg', 'image/png' => 'png', 'image/webp' => 'webp']);
        if (is_string($img)) error_response($img, 422);
        $photo = field_save($img[0], $img[1]);
    }
    $pdo->prepare("INSERT INTO field_visits (company_id, employee_id, customer_name, customer_phone, address, purpose, status, started_at, start_lat, start_lng, photo_file)
                   VALUES (?,?,?,?,?,?, 'active', UTC_TIMESTAMP(), ?, ?, ?)")
        ->execute([cid(), $eid, $name, mb_substr(trim((string)($b['customer_phone'] ?? '')), 0, 40) ?: null,
                   mb_substr(trim((string)($b['address'] ?? '')), 0, 255) ?: null, mb_substr(trim((string)($b['purpose'] ?? '')), 0, 255) ?: null, $lat, $lng, $photo]);
    $id = (int)$pdo->lastInsertId();
    $pdo->prepare("INSERT INTO field_points (visit_id, lat, lng, recorded_at) VALUES (?,?,?, UTC_TIMESTAMP())")->execute([$id, $lat, $lng]);
    json_response(['success' => true, 'data' => field_view(field_get($pdo, $id))], 201);
}

function field_points(PDO $pdo, int $id, array $b): void {
    $v = field_require_owner_active($pdo, $id);
    $pts = $b['points'] ?? null;
    if (!is_array($pts) || !$pts) error_response('points is required', 422);
    if (count($pts) > 200) error_response('Send at most 200 points at a time', 422);
    $last = $pdo->prepare("SELECT lat, lng FROM field_points WHERE visit_id = ? ORDER BY recorded_at DESC, id DESC LIMIT 1");
    $last->execute([$id]);
    $prev = $last->fetch();
    $plat = $prev ? (float)$prev['lat'] : (float)$v['start_lat'];
    $plng = $prev ? (float)$prev['lng'] : (float)$v['start_lng'];
    $ins = $pdo->prepare("INSERT INTO field_points (visit_id, lat, lng, recorded_at) VALUES (?,?,?,?)");
    $added = 0; $dist = 0.0; $now = time();
    foreach ($pts as $p) {
        $lat = field_coord($p['lat'] ?? null, 90); $lng = field_coord($p['lng'] ?? null, 180);
        if ($lat === null || $lng === null) continue;
        $t = isset($p['t']) && is_numeric($p['t']) ? (int)$p['t'] : $now;              // unix seconds, as recorded on the phone
        if ($t > $now + 60) $t = $now;                                                  // never from the future
        if ($t < strtotime($v['started_at'] . ' UTC') - 60) continue;                   // nothing from before the visit started
        $seg = field_km($plat, $plng, $lat, $lng);
        if ($seg < 100000) $dist += $seg;                                               // a 100 km jump is a GPS glitch, not walking
        $ins->execute([$id, $lat, $lng, gmdate('Y-m-d H:i:s', $t)]);
        $plat = $lat; $plng = $lng; $added++;
    }
    if ($dist > 0) $pdo->prepare("UPDATE field_visits SET distance_m = distance_m + ? WHERE id = ?")->execute([(int)round($dist), $id]);
    json_response(['success' => true, 'data' => ['added' => $added, 'distance_m' => (int)$v['distance_m'] + (int)round($dist)]]);
}

function field_finish(PDO $pdo, int $id, array $b): void {
    $v = field_require_owner_active($pdo, $id);
    $lat = field_coord($b['lat'] ?? null, 90); $lng = field_coord($b['lng'] ?? null, 180);
    if ($lat === null || $lng === null) error_response('Your location is required to finish the visit', 422);
    $sig = null; $photo = $v['photo_file'];
    if (!empty($b['signature_base64'])) {
        $img = field_decode_image((string)$b['signature_base64'], FIELD_MAX_SIGNATURE, ['image/png' => 'png']);
        if (is_string($img)) error_response($img, 422);
        $sig = field_save($img[0], $img[1]);
    }
    if (!empty($b['photo_base64'])) {
        $img = field_decode_image((string)$b['photo_base64'], FIELD_MAX_PHOTO, ['image/jpeg' => 'jpg', 'image/png' => 'png', 'image/webp' => 'webp']);
        if (is_string($img)) error_response($img, 422);
        $photo = field_save($img[0], $img[1]);
    }
    $last = $pdo->prepare("SELECT lat, lng FROM field_points WHERE visit_id = ? ORDER BY recorded_at DESC, id DESC LIMIT 1");
    $last->execute([$id]);
    $prev = $last->fetch() ?: ['lat' => $v['start_lat'], 'lng' => $v['start_lng']];
    $seg = field_km((float)$prev['lat'], (float)$prev['lng'], $lat, $lng);
    $pdo->prepare("UPDATE field_visits SET status = 'done', ended_at = UTC_TIMESTAMP(), end_lat = ?, end_lng = ?, distance_m = distance_m + ?,
                   signature_file = ?, signed_name = ?, notes = ?, photo_file = ? WHERE id = ? AND company_id = ?")
        ->execute([$lat, $lng, $seg < 100000 ? (int)round($seg) : 0, $sig, mb_substr(trim((string)($b['signed_name'] ?? '')), 0, 150) ?: null,
                   mb_substr(trim((string)($b['notes'] ?? '')), 0, 2000) ?: null, $photo, $id, cid()]);
    $pdo->prepare("INSERT INTO field_points (visit_id, lat, lng, recorded_at) VALUES (?,?,?, UTC_TIMESTAMP())")->execute([$id, $lat, $lng]);
    $out = field_view(field_get($pdo, $id));
    if ($out['flags']) notify_manager_of($pdo, (int)$v['employee_id'], 'field', 'Visit closed with a gap', $v['customer_name'] . ': ' . implode(', ', $out['flags']), ['visit_id' => $id]);
    json_response(['success' => true, 'data' => $out]);
}

function field_cancel(PDO $pdo, int $id): void {
    field_require_owner_active($pdo, $id);
    $pdo->prepare("UPDATE field_visits SET status = 'cancelled', ended_at = UTC_TIMESTAMP() WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
    json_response(['success' => true, 'data' => field_view(field_get($pdo, $id))]);
}

function field_scope_sql(PDO $pdo): string {
    if (is_hr()) return '';
    $ids = [];
    if (own_employee_id() > 0) $ids[] = own_employee_id();
    if (has_direct_reports($pdo)) {
        $s = $pdo->prepare("SELECT id FROM employees WHERE company_id = ? AND manager_id = ?");
        $s->execute([cid(), own_employee_id()]);
        foreach ($s->fetchAll(PDO::FETCH_COLUMN) as $x) $ids[] = (int)$x;
    }
    return ' AND v.employee_id IN (' . implode(',', $ids ?: [-1]) . ')';
}

function field_list(PDO $pdo): void {
    $where = 'v.company_id = ?'; $p = [cid()];
    $scope = field_scope_sql($pdo);
    if (!empty($_GET['employee_id'])) { $where .= ' AND v.employee_id = ?'; $p[] = (int)$_GET['employee_id']; }
    if (!empty($_GET['date']) && preg_match('/^\d{4}-\d{2}-\d{2}$/', (string)$_GET['date'])) { $where .= ' AND DATE(v.started_at) = ?'; $p[] = $_GET['date']; }
    if (!empty($_GET['status']) && in_array($_GET['status'], ['active', 'done', 'cancelled'], true)) { $where .= ' AND v.status = ?'; $p[] = $_GET['status']; }
    $s = $pdo->prepare("SELECT v.*, CONCAT(e.first_name, ' ', e.last_name) AS employee_name FROM field_visits v JOIN employees e ON e.id = v.employee_id
                        WHERE $where $scope ORDER BY v.started_at DESC LIMIT 200");
    $s->execute($p);
    json_response(['success' => true, 'data' => array_map('field_view', $s->fetchAll())]);
}

function field_one(PDO $pdo, int $id): void {
    $v = field_get($pdo, $id);
    $out = field_view($v);
    $pts = $pdo->prepare("SELECT lat, lng, recorded_at FROM field_points WHERE visit_id = ? ORDER BY recorded_at, id");
    $pts->execute([$id]);
    $rows = $pts->fetchAll();
    if (count($rows) > 500) {                                       // keep the shape, drop the weight
        $step = count($rows) / 500.0; $keep = [];
        for ($i = 0; $i < 500; $i++) $keep[] = $rows[(int)floor($i * $step)];
        $keep[] = end($rows);
        $rows = $keep;
    }
    $out['route'] = array_map(fn($r) => ['lat' => (float)$r['lat'], 'lng' => (float)$r['lng'], 'at' => $r['recorded_at']], $rows);
    json_response(['success' => true, 'data' => $out]);
}

function field_summary(PDO $pdo): void {
    if (!is_hr() && !has_direct_reports($pdo)) error_response('Forbidden. Insufficient permissions.', 403);
    $from = preg_match('/^\d{4}-\d{2}-\d{2}$/', (string)($_GET['from'] ?? '')) ? $_GET['from'] : gmdate('Y-m-d', time() - 6 * 86400);
    $to = preg_match('/^\d{4}-\d{2}-\d{2}$/', (string)($_GET['to'] ?? '')) ? $_GET['to'] : gmdate('Y-m-d');
    $scope = field_scope_sql($pdo);
    $s = $pdo->prepare("SELECT v.employee_id, CONCAT(e.first_name, ' ', e.last_name) AS employee_name, COUNT(*) AS visits,
                        SUM(v.status = 'done') AS done, SUM(v.distance_m) AS distance_m,
                        SUM(TIMESTAMPDIFF(MINUTE, v.started_at, COALESCE(v.ended_at, UTC_TIMESTAMP()))) AS minutes,
                        SUM(v.status = 'done' AND v.signature_file IS NOT NULL) AS signed, SUM(v.status = 'done' AND v.photo_file IS NOT NULL) AS photos
                        FROM field_visits v JOIN employees e ON e.id = v.employee_id
                        WHERE v.company_id = ? AND DATE(v.started_at) BETWEEN ? AND ? AND v.status != 'cancelled' $scope GROUP BY v.employee_id ORDER BY visits DESC");
    $s->execute([cid(), $from, $to]);
    $rows = array_map(fn($r) => ['employee_id' => (int)$r['employee_id'], 'employee_name' => $r['employee_name'], 'visits' => (int)$r['visits'], 'done' => (int)$r['done'],
        'km' => round((int)$r['distance_m'] / 1000, 1), 'minutes' => (int)$r['minutes'], 'signed' => (int)$r['signed'], 'photos' => (int)$r['photos']], $s->fetchAll());
    json_response(['success' => true, 'data' => ['from' => $from, 'to' => $to, 'people' => $rows,
        'totals' => ['visits' => array_sum(array_column($rows, 'visits')), 'km' => round(array_sum(array_column($rows, 'km')), 1), 'minutes' => array_sum(array_column($rows, 'minutes'))]]]);
}

function field_stream(PDO $pdo, int $id, string $kind): void {
    $v = field_get($pdo, $id);
    $file = $kind === 'photo' ? $v['photo_file'] : $v['signature_file'];
    if (!$file) error_response('No ' . $kind . ' for this visit', 404);
    $root = realpath(__DIR__ . '/../uploads/field');
    $full = $root ? realpath($root . '/' . cid() . '/' . $file) : false;
    if (!$full || strpos($full, $root) !== 0 || !is_file($full)) error_response('File not found', 404);
    header('Content-Type: ' . ((new finfo(FILEINFO_MIME_TYPE))->file($full) ?: 'application/octet-stream'));
    header('Cache-Control: private, max-age=300');
    header('Content-Length: ' . filesize($full));
    readfile($full);
    exit;
}
