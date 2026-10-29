<?php
/**
 * Attendance Rules API handler (company-scoped). Only admins change rules.
 */
function handle_attendance_rules(string $path, string $method, array $body): void {
    $pdo      = getDB();
    $segments = explode('/', $path);
    $sub      = $segments[1] ?? '';

    // GET /attendance-rules/active
    if ($sub === 'active' && $method === 'GET') {
        attendance_rules_get_active($pdo);
        return;
    }

    $id = ($sub !== '' && is_numeric($sub)) ? intval($sub) : null;

    if ($id !== null) {
        switch ($method) {
            case 'GET':    attendance_rules_get_one($id, $pdo); break;
            case 'PUT':    require_admin(); attendance_rules_update($id, $body, $pdo); break;
            case 'DELETE': require_admin(); attendance_rules_delete($id, $pdo); break;
            default:       error_response('Method not allowed', 405);
        }
    } else {
        switch ($method) {
            case 'GET':  attendance_rules_list($pdo); break;
            case 'POST': require_admin(); attendance_rules_create($body, $pdo); break;
            default:     error_response('Method not allowed', 405);
        }
    }
}

/** Reject impossible coordinates / radius so a typo cannot lock everybody out. */
function attendance_rules_validate(array $body): void {
    if (!empty($body['location_enabled'])) {
        if (!isset($body['location_lat'], $body['location_lng']) || !is_numeric($body['location_lat']) || !is_numeric($body['location_lng'])) {
            error_response('Enter the workplace latitude and longitude', 422);
        }
        if (abs((float)$body['location_lat']) > 90 || abs((float)$body['location_lng']) > 180) error_response('Coordinates are out of range', 422);
        $r = isset($body['location_radius_km']) ? (float)$body['location_radius_km'] : 0.2;
        if ($r < 0.01 || $r > 50) error_response('Radius must be between 10 m and 50 km', 422);
    }
    if (isset($body['network_type']) && !in_array($body['network_type'], ['wifi', 'wired'], true)) error_response('network_type must be wifi or wired', 422);
    if (!empty($body['wifi_enabled']) && ($body['network_type'] ?? 'wifi') === 'wired') {
        // a wired (cable) network is recognised by its gateway (router) address
        if (!filter_var(trim((string)($body['wired_gateway'] ?? '')), FILTER_VALIDATE_IP)) error_response('Connect to the wired network first so its gateway address can be read', 422);
    } elseif (!empty($body['wifi_enabled']) && trim((string)($body['wifi_ssid'] ?? '')) === '' && trim((string)($body['wifi_bssid'] ?? '')) === '') {
        error_response('Enter the Wi-Fi name', 422);
    }
    if (isset($body['match_mode']) && !in_array($body['match_mode'], ['any', 'all'], true)) error_response('match_mode must be any or all', 422);
}

function attendance_rules_active_row(PDO $pdo): ?array {
    $stmt = $pdo->prepare("SELECT * FROM attendance_rules WHERE company_id = ? AND is_active = 1 LIMIT 1");
    $stmt->execute([cid()]);
    return $stmt->fetch() ?: null;
}

function attendance_rules_list(PDO $pdo): void {
    $stmt = $pdo->prepare("SELECT * FROM attendance_rules WHERE company_id = ? ORDER BY created_at DESC");
    $stmt->execute([cid()]);
    json_response(['success' => true, 'data' => $stmt->fetchAll()]);
}

function attendance_rules_get_active(PDO $pdo): void {
    json_response(['success' => true, 'data' => attendance_rules_active_row($pdo)]);
}

function attendance_rules_get_one(int $id, PDO $pdo): void {
    $stmt = $pdo->prepare("SELECT * FROM attendance_rules WHERE id = ? AND company_id = ?");
    $stmt->execute([$id, cid()]);
    $rule = $stmt->fetch();
    if (!$rule) {
        error_response('Attendance rule not found', 404);
    }
    json_response(['success' => true, 'data' => $rule]);
}

function attendance_rules_create(array $body, PDO $pdo): void {
    $name = trim($body['name'] ?? '');
    if ($name === '') {
        error_response('Rule name is required');
    }

    $isActive = isset($body['is_active']) ? (int)$body['is_active'] : 0;
    attendance_rules_validate($body);

    $stmt = $pdo->prepare(
        "INSERT INTO attendance_rules
            (company_id, name, is_active, location_enabled, location_lat, location_lng,
             location_radius_km, wifi_enabled, wifi_ssid, wifi_bssid, match_mode, network_type, wired_gateway, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())"
    );
    $stmt->execute([
        cid(),
        $name,
        $isActive,
        isset($body['location_enabled']) ? (int)$body['location_enabled'] : 0,
        $body['location_lat']        ?? null,
        $body['location_lng']        ?? null,
        $body['location_radius_km']  ?? null,
        isset($body['wifi_enabled']) ? (int)$body['wifi_enabled'] : 0,
        ($body['wifi_ssid'] ?? '') !== '' ? trim((string)$body['wifi_ssid']) : null,
        ($body['wifi_bssid'] ?? '') !== '' ? strtolower(trim((string)$body['wifi_bssid'])) : null,
        ($body['match_mode'] ?? 'any') === 'all' ? 'all' : 'any',
        ($body['network_type'] ?? 'wifi') === 'wired' ? 'wired' : 'wifi',
        ($body['network_type'] ?? 'wifi') === 'wired' && ($body['wired_gateway'] ?? '') !== '' ? trim((string)$body['wired_gateway']) : null,
    ]);

    $newId = (int)$pdo->lastInsertId();
    audit($pdo, 'create', 'attendance_rule', $newId, $body);
    attendance_rules_get_one($newId, $pdo);
}

function attendance_rules_update(int $id, array $body, PDO $pdo): void {
    if (!in_company($pdo, 'attendance_rules', $id)) {
        error_response('Attendance rule not found', 404);
    }

    attendance_rules_validate($body);
    $fields = [];
    $params = [];
    foreach (['name', 'location_enabled', 'location_lat', 'location_lng',
              'location_radius_km', 'wifi_enabled', 'wifi_ssid', 'wifi_bssid', 'match_mode', 'is_active', 'network_type', 'wired_gateway'] as $field) {
        if (array_key_exists($field, $body)) {
            $fields[] = "$field = ?";
            $params[]  = in_array($field, ['is_active', 'location_enabled', 'wifi_enabled'], true)
                ? (int)$body[$field]
                : ($body[$field] === '' ? null : $body[$field]);
        }
    }
    if (empty($fields)) {
        error_response('No fields to update');
    }

    $params[] = $id;
    $params[] = cid();
    $pdo->prepare("UPDATE attendance_rules SET " . implode(', ', $fields) . " WHERE id = ? AND company_id = ?")->execute($params);
    audit($pdo, 'update', 'attendance_rule', $id, $body);
    attendance_rules_get_one($id, $pdo);
}

function attendance_rules_delete(int $id, PDO $pdo): void {
    if (!in_company($pdo, 'attendance_rules', $id)) {
        error_response('Attendance rule not found', 404);
    }
    $pdo->prepare("DELETE FROM attendance_rules WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
    audit($pdo, 'delete', 'attendance_rule', $id);
    json_response(['success' => true, 'message' => 'Attendance rule deleted']);
}
