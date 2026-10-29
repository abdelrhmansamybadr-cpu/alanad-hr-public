<?php
/**
 * Convert snake_case keys to camelCase, recursively.
 * The Flutter app (written against the Node API) expects camelCase and
 * un-wrapped payloads, so every response is normalised here in one place.
 */
function hr_camelize_keys($value) {
    if (!is_array($value)) {
        return $value;
    }
    // MySQL DECIMAL columns come back as strings; the app parses them as num.
    $numeric = ['baseSalary', 'bonus', 'deductions', 'netPay', 'hoursWorked',
                'locationLat', 'locationLng', 'locationRadiusKm', 'totalPayroll',
                'daysPerMonth', 'daysPerYear'];
    $isEmployee = array_key_exists('first_name', $value) || array_key_exists('firstName', $value);
    $out = [];
    foreach ($value as $k => $v) {
        if (is_string($k) && strpos($k, '_') !== false) {
            $k = lcfirst(str_replace(' ', '', ucwords(str_replace('_', ' ', $k))));
        }
        // 'counts' is a status->number map whose keys are data (e.g. talent_pool); keep them.
        $v = ($k === 'counts') ? $v : hr_camelize_keys($v);
        if (is_string($v) && is_numeric($v) &&
            (in_array($k, $numeric, true) || ($k === 'salary' && $isEmployee))) {
            $v = $v + 0;
            if (is_int($v)) $v = (float)$v;
        }
        // TINYINT(1) flags come back as 0/1; the app reads them as bool.
        if (in_array($k, ['isActive', 'locationEnabled', 'wifiEnabled', 'isRequired', 'enabled', 'voided', 'applied', 'closed', 'checkInInside', 'checkOutInside', 'lastPingInside'], true)
            && (is_int($v) || $v === '0' || $v === '1')) {
            $v = ((int)$v) === 1;
        }
        // TIME columns come back as HH:MM:SS; the app and portal use HH:MM.
        if (is_string($v) && in_array($k, ['startTime', 'endTime', 'checkIn', 'checkOut'], true)
            && preg_match('/^\d{2}:\d{2}:\d{2}$/', $v)) {
            $v = substr($v, 0, 5);
        }
        // The app reads these as non-null strings; never send null for them.
        if ($v === null && in_array($k, ['location', 'description', 'content', 'authorName', 'employeeName', 'jobTitle', 'color', 'period'], true)) {
            $v = '';
        }
        if ($k === 'email' && is_string($v) && str_ends_with(strtolower($v), '@no-email.invalid')) $v = '';
        $out[$k] = $v;
    }
    return $out;
}

/**
 * Convert camelCase request keys (sent by the mobile app) to snake_case,
 * recursively, so the handlers can keep reading snake_case fields.
 */
function hr_snake_keys($value) {
    if (!is_array($value)) {
        return $value;
    }
    $out = [];
    foreach ($value as $k => $v) {
        if (is_string($k)) {
            $k = strtolower(preg_replace('/(?<!^)[A-Z]/', '_$0', $k));
        }
        $out[$k] = hr_snake_keys($v);
    }
    return $out;
}

/**
 * Convert the internal {success, data|user, ...} envelope into the plain
 * payload shape the mobile app expects.
 */
function hr_normalize_payload($data) {
    if (!is_array($data)) {
        return $data;
    }
    // Errors keep their shape: {error: "..."}
    if (isset($data['error'])) {
        return ['error' => $data['error']];
    }
    if (($data['success'] ?? null) === true) {
        // {success, data: X}  ->  X
        if (array_key_exists('data', $data)) {
            return hr_camelize_keys($data['data']);
        }
        // {success, user: X}  ->  X   (login keeps token + user together)
        if (array_key_exists('user', $data) && !array_key_exists('token', $data)) {
            return hr_camelize_keys($data['user']);
        }
        unset($data['success']);
    }
    return hr_camelize_keys($data);
}

/**
 * Send a JSON response with the given data and HTTP status code.
 *
 * @param mixed $data
 * @param int   $status HTTP status code
 */
function json_response($data, int $status = 200): void {
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(hr_normalize_payload($data), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRESERVE_ZERO_FRACTION);
    exit;
}

/**
 * Send an error JSON response.
 *
 * @param string $message Error message
 * @param int    $status  HTTP status code (default 400)
 */
function error_response(string $message, int $status = 400): void {
    json_response(['error' => $message], $status);
}

/**
 * Send a success JSON response wrapping the provided data.
 *
 * @param mixed $data
 */
function success_response($data): void {
    json_response(['data' => $data, 'success' => true]);
}
