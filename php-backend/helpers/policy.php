<?php
/**
 * Automatic attendance policy, location/Wi-Fi zone checks, audit log.
 *
 * Nothing in here trusts what a client says about lateness: the server derives
 * status (present / late / half_day / absent) from the shift, the company policy,
 * the time of each action and the time spent outside the allowed zone.
 */

// ------------------------------------------------------------------ JSON settings

function policy_load(PDO $pdo, string $column, array $defaults): array {
    $key = cid() . ':' . $column;
    if (!isset($GLOBALS['HR_POLICY_CACHE'][$key])) {
        $c = company_get($pdo, cid());
        $stored = ($c && !empty($c[$column])) ? json_decode($c[$column], true) : null;
        $GLOBALS['HR_POLICY_CACHE'][$key] = array_merge($defaults, is_array($stored) ? array_intersect_key($stored, $defaults) : []);
    }
    return $GLOBALS['HR_POLICY_CACHE'][$key];
}

function policy_from_row(array $company, string $column, array $defaults): array {
    $stored = !empty($company[$column]) ? json_decode($company[$column], true) : null;
    return array_merge($defaults, is_array($stored) ? array_intersect_key($stored, $defaults) : []);
}

function att_policy_defaults(): array {
    return [
        'default_start'             => '09:00',   // used when an employee has no shift
        'default_end'               => '17:00',
        'early_leave_grace_minutes' => 10,        // leaving this much before shift end is still "on time"
        'half_day_late_minutes'     => 120,       // arriving this late counts as a half day (0 = off)
        'half_day_early_minutes'    => 120,       // leaving this early counts as a half day (0 = off)
        'half_day_min_hours_pct'    => 50,        // working less than this % of the shift = half day (0 = off)
        'absent_late_minutes'       => 0,         // arriving this late counts as absent (0 = off)
        'absent_min_hours_pct'      => 0,         // working less than this % of the shift = absent (0 = off)
        'out_zone_half_day_minutes' => 120,       // this long outside the work zone = half day (0 = off)
        'missed_checkout'           => 'flag',    // flag | half_day | absent
        'auto_close_after_hours'    => 4,         // hours after shift end an open day is closed
        'overtime_after_minutes'    => 30,        // minutes beyond the shift before overtime starts
        'allow_checkout_outside'    => true,      // may employees check out away from the workplace?
        'track_location'            => true,      // app sends location pings while checked in
        'ping_interval_minutes'     => 5,
        'max_ping_gap_minutes'      => 30,        // longest gap a single ping may account for
        'reminders'                 => true,      // remind employees to check in / out
        'block_mock_location'       => true,      // refuse check-in / out while the phone reports a fake GPS location
        'block_shared_device'       => false,     // refuse check-in from a phone another employee already used today (false = only flag it)
        'offline_max_hours'         => 12,        // an offline check-in / out may be synced up to this many hours later (0 = off)
        'leave_preset'              => 'none',    // none | egypt (annual leave by years of service and age)
    ];
}
function att_policy(PDO $pdo): array { return policy_load($pdo, 'attendance_policy', att_policy_defaults()); }

function points_config_defaults(): array {
    return [
        'enabled'            => true,
        'kudos_green_every'  => 5,            // every Nth kudos an employee receives earns one green point (0 = off)
        'late_color'         => 'none',       // none | red
        'half_day_color'     => 'red',
        'absent_color'       => 'black',
        'missed_checkout_color' => 'none',    // none | red
        'red_cost'           => 2,            // green points that cancel one red point
        'black_cost'         => 5,            // green points that cancel one black point
        'cancel_order'       => 'black_first',// black_first | red_first
        'streak_days'        => 30,           // consecutive green days for a level-up
        'levels'             => ['Rookie', 'Bronze', 'Silver', 'Gold', 'Platinum', 'Diamond', 'Legend'],
        'show_leaderboard'   => true,
    ];
}
function points_config(PDO $pdo): array { return policy_load($pdo, 'points_config', points_config_defaults()); }

function payroll_policy_defaults(): array {
    return [
        'use_attendance'          => true,
        'day_divisor'             => 'working_days', // working_days | 30
        'deduct_absent'           => true,
        'deduct_unpaid_leave'     => true,
        'half_day_fraction'       => 0.5,
        'late_deduction'          => 'none',         // none | hourly (late minutes x hourly rate)
        'overtime_enabled'        => true,
        'overtime_multiplier'     => 1.5,
        'perfect_attendance_bonus'=> 0,
        'shift_hours'             => 8,
        'insurance_pct'           => 0.0,            // employee social-insurance share, % of salary (0 = off)
        'insurance_cap'           => 0.0,            // monthly salary the insurance is calculated on, at most (0 = no cap)
        'tax_mode'                => 'none',         // none | flat | brackets
        'tax_flat_pct'            => 0.0,
        'tax_monthly_exemption'   => 0.0,            // part of the monthly pay that is not taxed
        'tax_brackets'            => [],             // monthly steps as 'upTo|rate', e.g. '5000|0', '10000|10', '|20' (empty upTo = the rest)
    ];
}
function payroll_policy(PDO $pdo): array {
    $pol = policy_load($pdo, 'payroll_policy', payroll_policy_defaults());
    // Feature `local_laws`: with a country law pack active, insurance / tax / overtime follow the pack
    return function_exists('law_overlay_payroll_policy') ? law_overlay_payroll_policy($pdo, $pol) : $pol;
}

/** Validate + store one of the three JSON policies coming from the admin. */
function policy_clean(string $kind, array $in, array $current): array {
    $defs = $kind === 'attendance_policy' ? att_policy_defaults() : ($kind === 'points_config' ? points_config_defaults() : payroll_policy_defaults());
    $out = $current;
    foreach ($defs as $k => $def) {
        if (!array_key_exists($k, $in)) continue;
        $v = $in[$k];
        if (is_bool($def))       $out[$k] = filter_var($v, FILTER_VALIDATE_BOOLEAN);
        elseif (is_int($def))    $out[$k] = max(0, min(100000, (int)$v));
        elseif (is_float($def))  $out[$k] = max(0, min(1000, (float)$v));
        elseif (is_array($def))  { $out[$k] = array_values(array_filter(array_map(fn($s) => mb_substr(trim((string)$s), 0, 30), (array)$v), fn($s) => $s !== '')) ?: $def; }
        else                     $out[$k] = mb_substr(trim((string)$v), 0, 40);
    }
    // enumerations
    $enum = [
        'missed_checkout' => ['flag', 'half_day', 'absent'],
        'late_color' => ['none', 'red'], 'half_day_color' => ['none', 'red'], 'absent_color' => ['none', 'red', 'black'],
        'missed_checkout_color' => ['none', 'red'], 'cancel_order' => ['black_first', 'red_first'],
        'day_divisor' => ['working_days', '30'], 'late_deduction' => ['none', 'hourly'],
        'leave_preset' => ['none', 'egypt'], 'tax_mode' => ['none', 'flat', 'brackets'],
    ];
    foreach ($enum as $k => $allowed) { if (isset($out[$k]) && !in_array($out[$k], $allowed, true)) $out[$k] = $defs[$k]; }
    foreach (['default_start', 'default_end'] as $k) { if (isset($out[$k]) && !preg_match('/^\d{2}:\d{2}$/', $out[$k])) $out[$k] = $defs[$k]; }
    // money-sized numbers may exceed the generic limit above
    foreach (['insurance_cap', 'tax_monthly_exemption'] as $k) {
        if (array_key_exists($k, $defs) && array_key_exists($k, $in)) $out[$k] = max(0.0, min(10000000.0, (float)$in[$k]));
    }
    if (isset($out['insurance_pct'])) $out['insurance_pct'] = max(0.0, min(100.0, (float)$out['insurance_pct']));
    if (isset($out['tax_flat_pct']))  $out['tax_flat_pct']  = max(0.0, min(100.0, (float)$out['tax_flat_pct']));
    if (isset($out['tax_brackets']) && is_array($out['tax_brackets'])) {
        $out['tax_brackets'] = array_values(array_filter($out['tax_brackets'], fn($b) => preg_match('/^\d*(\.\d+)?\|\d{1,3}(\.\d+)?$/', (string)$b)));
    }
    if (isset($out['offline_max_hours'])) $out['offline_max_hours'] = min(72, $out['offline_max_hours']);
    if (isset($out['red_cost']))   $out['red_cost']   = max(1, $out['red_cost']);
    if (isset($out['black_cost'])) $out['black_cost'] = max(1, $out['black_cost']);
    if (isset($out['streak_days'])) $out['streak_days'] = max(1, $out['streak_days']);
    if (isset($out['ping_interval_minutes'])) $out['ping_interval_minutes'] = max(1, $out['ping_interval_minutes']);
    if (isset($out['max_ping_gap_minutes']))  $out['max_ping_gap_minutes']  = max(5, $out['max_ping_gap_minutes']);
    return $out;
}

// ------------------------------------------------------------------ audit

function audit(PDO $pdo, string $action, string $entity, ?int $entityId = null, $details = null): void {
    try {
        $u = me();
        $pdo->prepare("INSERT INTO audit_log (company_id, user_id, user_name, action, entity, entity_id, details) VALUES (?,?,?,?,?,?,?)")
            ->execute([cid(), (int)$u['id'], $u['name'] ?? null, $action, $entity, $entityId,
                       $details === null ? null : (is_string($details) ? mb_substr($details, 0, 2000) : json_encode($details, JSON_UNESCAPED_UNICODE))]);
    } catch (Throwable $e) { /* auditing must never break the request */ }
}

// ------------------------------------------------------------------ time + shift helpers

function att_min(?string $t): ?int {
    if ($t === null || $t === '') return null;
    $p = explode(':', $t);
    return ((int)$p[0]) * 60 + (int)($p[1] ?? 0);
}

function att_now(PDO $pdo): DateTime {
    // An offline check-in / out synced later is evaluated at the moment it really happened (set by the attendance handler).
    if (!empty($GLOBALS['HR_NOW_OVERRIDE']) && $GLOBALS['HR_NOW_OVERRIDE'] instanceof DateTime) return clone $GLOBALS['HR_NOW_OVERRIDE'];
    $c  = company_get($pdo, cid());
    $tz = @timezone_open($c['timezone'] ?? 'UTC') ?: new DateTimeZone('UTC');
    // The automated tests move the clock with a header; this only works where config/database.php opts in (never in production).
    if (defined('HR_ALLOW_TEST_CLOCK') && HR_ALLOW_TEST_CLOCK && !empty($_SERVER['HTTP_X_TEST_NOW'])) {
        try { return new DateTime((string)$_SERVER['HTTP_X_TEST_NOW'], $tz); } catch (Throwable $e) { /* fall through */ }
    }
    return new DateTime('now', $tz);
}

/** The shift an employee works: their own, or the company default from the policy. */
function att_shift(PDO $pdo, array $emp): array {
    $p = att_policy($pdo);
    if (!empty($emp['shift_start'])) {
        return ['name' => $emp['shift_name'] ?? null, 'start' => substr($emp['shift_start'], 0, 5), 'end' => substr($emp['shift_end'], 0, 5),
                'days' => $emp['shift_days'] ?: null, 'default' => false];
    }
    return ['name' => null, 'start' => $p['default_start'], 'end' => $p['default_end'], 'days' => null, 'default' => true];
}

function att_shift_len(array $shift): int {
    $len = att_min($shift['end']) - att_min($shift['start']);
    return $len <= 0 ? $len + 1440 : $len;
}

function att_is_workday(PDO $pdo, array $shift, string $date): bool {
    $dow = strtolower((new DateTime($date))->format('D'));
    if ($shift['days']) return in_array($dow, array_map('trim', explode(',', strtolower($shift['days']))), true);
    $c = company_get($pdo, cid());
    return !in_array($dow, array_map('trim', explode(',', strtolower($c['weekend_days'] ?? 'fri,sat'))), true);
}

/**
 * Derive the day's result from the times.  Returns
 * [status, late_minutes, early_leave_minutes, overtime_minutes, hours_worked, flags[]].
 */
function att_evaluate(PDO $pdo, array $shift, ?string $in, ?string $out, int $outZone, bool $dayOver): array {
    $p     = att_policy($pdo);
    $c     = company_get($pdo, cid());
    $grace = (int)($c['late_grace_minutes'] ?? 15);
    $start = att_min($shift['start']);
    $len   = att_shift_len($shift);
    $rel   = function (int $m) use ($start): int { $r = $m - $start; if ($r < -720) $r += 1440; return $r; };

    $late = 0; $early = 0; $ot = 0; $worked = null; $flags = [];
    $relIn = ($in !== null && $in !== '') ? $rel(att_min($in)) : null;
    if ($relIn !== null) $late = max(0, $relIn);

    $half = false; $absent = false;
    if ($p['absent_late_minutes'] > 0 && $late >= $p['absent_late_minutes']) $absent = true;
    if ($p['half_day_late_minutes'] > 0 && $late >= $p['half_day_late_minutes']) $half = true;

    if ($relIn !== null && $out) {
        $relOut = $rel(att_min($out));
        if ($relOut < $relIn) $relOut += 1440;
        $gross  = $relOut - $relIn;
        $worked = max(0, $gross - $outZone);
        $early  = max(0, $len - $relOut);
        $ot     = max(0, $relOut - $len);
        if ($ot < $p['overtime_after_minutes']) $ot = 0;
        if ($p['absent_min_hours_pct'] > 0 && $worked < $len * $p['absent_min_hours_pct'] / 100) $absent = true;
        if ($p['half_day_early_minutes'] > 0 && $early >= $p['half_day_early_minutes']) $half = true;
        if ($p['half_day_min_hours_pct'] > 0 && $worked < $len * $p['half_day_min_hours_pct'] / 100) $half = true;
        if ($early > $p['early_leave_grace_minutes']) $flags[] = 'early_leave';
    } elseif ($relIn !== null && $dayOver) {
        $flags[] = 'missed_checkout';
        if ($p['missed_checkout'] === 'half_day') $half = true;
        if ($p['missed_checkout'] === 'absent')   $absent = true;
    }
    if ($outZone > 0) $flags[] = 'left_zone';
    if ($p['out_zone_half_day_minutes'] > 0 && $outZone >= $p['out_zone_half_day_minutes']) $half = true;

    $status = 'present';
    if ($absent)             $status = 'absent';
    elseif ($half)           $status = 'half_day';
    elseif ($late > $grace)  $status = 'late';
    if ($late > $grace) $flags[] = 'late';

    return [
        'status' => $status, 'late_minutes' => $late, 'early_leave_minutes' => $early, 'overtime_minutes' => $ot,
        'hours_worked' => $worked === null ? null : round($worked / 60, 2), 'flags' => array_values(array_unique($flags)),
    ];
}

function att_employee_row(PDO $pdo, int $employeeId): ?array {
    $s = $pdo->prepare(
        "SELECT e.*, s.name AS shift_name, s.start_time AS shift_start, s.end_time AS shift_end, s.days AS shift_days
         FROM employees e LEFT JOIN shifts s ON s.id = e.shift_id WHERE e.id = ? AND e.company_id = ?"
    );
    $s->execute([$employeeId, cid()]);
    return $s->fetch() ?: null;
}

/** Re-derive and store an attendance row's automatic fields (status etc.). */
function att_apply(PDO $pdo, array $rec, ?array $emp = null, bool $dayOver = false): array {
    $emp = $emp ?: att_employee_row($pdo, (int)$rec['employee_id']);
    $shift = att_shift($pdo, $emp);
    $ev = att_evaluate($pdo, $shift, $rec['check_in'], $rec['check_out'], (int)$rec['out_zone_minutes'], $dayOver || !empty($rec['closed']));
    $pdo->prepare(
        "UPDATE attendance SET status = ?, late_minutes = ?, early_leave_minutes = ?, overtime_minutes = ?, hours_worked = ?, flags = ? WHERE id = ? AND company_id = ?"
    )->execute([$ev['status'], $ev['late_minutes'], $ev['early_leave_minutes'], $ev['overtime_minutes'], $ev['hours_worked'],
                $ev['flags'] ? implode(',', $ev['flags']) : null, $rec['id'], cid()]);
    return $ev;
}

/**
 * Close open days that were never checked out: yesterday's (or older) records, and today's
 * once the shift is over by more than the policy's auto-close window.
 */
function att_close_stale(PDO $pdo, ?int $employeeId = null): void {
    $now = att_now($pdo);
    $p = att_policy($pdo);
    $sql = "SELECT a.* FROM attendance a WHERE a.company_id = ? AND a.check_out IS NULL AND a.closed = 0 AND a.date <= ?";
    $args = [cid(), $now->format('Y-m-d')];
    if ($employeeId) { $sql .= " AND a.employee_id = ?"; $args[] = $employeeId; }
    $s = $pdo->prepare($sql . " LIMIT 200");
    $s->execute($args);
    foreach ($s->fetchAll() as $rec) {
        $emp = att_employee_row($pdo, (int)$rec['employee_id']);
        if (!$emp) continue;
        $shift = att_shift($pdo, $emp);
        $end = new DateTime($rec['date'] . ' ' . $shift['end'], $now->getTimezone());
        if (att_min($shift['end']) <= att_min($shift['start'])) $end->modify('+1 day');     // overnight shift
        $end->modify('+' . (int)$p['auto_close_after_hours'] . ' hours');
        if ($now < $end) continue;
        $pdo->prepare("UPDATE attendance SET closed = 1 WHERE id = ? AND company_id = ?")->execute([$rec['id'], cid()]);
        $rec['closed'] = 1;
        att_apply($pdo, $rec, $emp, true);
        if (function_exists('points_reeval')) points_reeval($pdo, (int)$rec['employee_id'], $rec['date']);
    }
}

// ------------------------------------------------------------------ zone (location / Wi-Fi)

function att_distance_m(float $lat1, float $lng1, float $lat2, float $lng2): float {
    $r  = 6371000.0;
    $p1 = deg2rad($lat1); $p2 = deg2rad($lat2);
    $dp = $p2 - $p1;      $dl = deg2rad($lng2 - $lng1);
    $a  = sin($dp / 2) ** 2 + cos($p1) * cos($p2) * sin($dl / 2) ** 2;
    return 2 * $r * asin(min(1, sqrt($a)));
}

/**
 * The day from which this employee's attendance is counted: the day the account was created, i.e. the first time the person
 * installed the app / opened the site and chose a password. null = never signed in yet, so nothing is counted (no absences, no deductions).
 */
function att_tracking_start(PDO $pdo, int $employeeId): ?string {
    static $cache = [];
    $k = cid() . ':' . $employeeId;
    if (!array_key_exists($k, $cache)) {
        $s = $pdo->prepare("SELECT MIN(created_at) FROM users WHERE employee_id = ? AND company_id = ? AND role = 'employee'");
        $s->execute([$employeeId, cid()]);
        $v = $s->fetchColumn();
        $cache[$k] = $v ? substr((string)$v, 0, 10) : null;
    }
    return $cache[$k];
}

function att_active_rules(PDO $pdo, ?array $emp = null): array {
    $mode = (string)($emp['attendance_mode'] ?? 'company');
    if ($mode === 'free') return [];                                   // exception: this person is not tied to a place
    if ($mode === 'rule' && !empty($emp['attendance_rule_id'])) {      // exception: a different place / method just for this person
        $s = $pdo->prepare("SELECT * FROM attendance_rules WHERE id = ? AND company_id = ?");
        $s->execute([(int)$emp['attendance_rule_id'], cid()]);
        return array_values(array_filter($s->fetchAll(), fn($r) => (int)$r['location_enabled'] === 1 || (int)$r['wifi_enabled'] === 1));
    }
    $s = $pdo->prepare("SELECT * FROM attendance_rules WHERE company_id = ? AND is_active = 1 ORDER BY id");
    $s->execute([cid()]);
    return array_values(array_filter($s->fetchAll(), fn($r) => (int)$r['location_enabled'] === 1 || (int)$r['wifi_enabled'] === 1));
}

function att_ssid_clean($s): string {
    $s = trim((string)$s, " \"'");
    return strcasecmp($s, '<unknown ssid>') === 0 ? '' : $s;
}

/**
 * Is the device inside an allowed zone?  Returns
 * ['constrained'=>bool,'inside'=>bool,'message'=>string,'distance_m'=>?float,'rule'=>?string,'via'=>?string]
 */
function att_zone(PDO $pdo, array $body, ?array $emp = null): array {
    $rules = att_active_rules($pdo, $emp);
    if (!$rules) return ['constrained' => false, 'inside' => true, 'message' => '', 'distance_m' => null, 'rule' => null, 'via' => null];

    $hasLoc = isset($body['lat'], $body['lng']) && is_numeric($body['lat']) && is_numeric($body['lng']);
    $ssid   = att_ssid_clean($body['ssid'] ?? '');
    $bssid  = strtolower(trim((string)($body['bssid'] ?? '')));
    $nearest = null; $messages = [];

    foreach ($rules as $r) {
        $locOn = (int)$r['location_enabled'] === 1 && $r['location_lat'] !== null && $r['location_lng'] !== null;
        $wired  = ($r['network_type'] ?? 'wifi') === 'wired';
        $wifiOn = (int)$r['wifi_enabled'] === 1 && ($wired ? !empty($r['wired_gateway']) : ($r['wifi_ssid'] !== null && $r['wifi_ssid'] !== '' || !empty($r['wifi_bssid'])));
        $locOk = null; $wifiOk = null; $dist = null;

        if ($locOn) {
            if ($hasLoc) {
                $dist = att_distance_m((float)$body['lat'], (float)$body['lng'], (float)$r['location_lat'], (float)$r['location_lng']);
                $radius = (float)($r['location_radius_km'] ?? 0.2) * 1000;
                $locOk = $dist <= $radius;
                if ($nearest === null || $dist < $nearest) $nearest = $dist;
                if (!$locOk) $messages[] = sprintf('You are %d m away from the workplace (allowed: %d m).', round($dist), round($radius));
            } else {
                $locOk = false;
                $messages[] = 'Location is required. Please turn on location services and try again.';
            }
        }
        if ($wifiOn && $wired) {
            // wired (cable) network: the device must be on a cable connection whose gateway is the company's
            $gw = trim((string)($body['gateway'] ?? ''));
            $wifiOk = ($body['link'] ?? '') === 'wired' && $gw !== '' && $gw === trim((string)$r['wired_gateway']);
            if (!$wifiOk) $messages[] = 'Connect this device to the company wired (cable) network to continue.';
        } elseif ($wifiOn) {
            if (!empty($r['wifi_bssid'])) $wifiOk = $bssid !== '' && strcasecmp($bssid, $r['wifi_bssid']) === 0;
            else                          $wifiOk = $ssid !== '' && strcasecmp($ssid, $r['wifi_ssid']) === 0;
            if (!$wifiOk) {
                $messages[] = $ssid === '' && $bssid === ''
                    ? 'The Wi-Fi name could not be read. Turn on location services and connect to the company Wi-Fi (' . $r['wifi_ssid'] . ').'
                    : 'Connect to the company Wi-Fi (' . ($r['wifi_ssid'] ?: $r['wifi_bssid']) . ') to continue.';
            }
        }

        $checks = array_values(array_filter([$locOk, $wifiOk], fn($x) => $x !== null));
        if (!$checks) continue;
        $ok = ($r['match_mode'] ?? 'any') === 'all' ? !in_array(false, $checks, true) : in_array(true, $checks, true);
        if ($ok) {
            $via = $locOk && $wifiOk ? 'location+wifi' : ($locOk ? 'location' : 'wifi');
            return ['constrained' => true, 'inside' => true, 'message' => '', 'distance_m' => $dist, 'rule' => $r['name'], 'via' => $via];
        }
    }
    return ['constrained' => true, 'inside' => false, 'message' => $messages ? $messages[0] : 'You are not at the workplace.',
            'distance_m' => $nearest, 'rule' => null, 'via' => null];
}
