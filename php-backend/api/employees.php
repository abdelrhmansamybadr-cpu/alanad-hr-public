<?php
/**
 * Employees API handler (company-scoped)
 *
 *   POST /employees/{id}/promote     {type, position?, salary?, department_id?, effective_date?, note?}  (HR)
 *   GET  /employees/{id}/promotions  career history (HR or the employee)
 *   POST /employees/{id}/terminate   {date?, reason?}    POST /employees/{id}/reinstate   (HR)
 */
require_once __DIR__ . '/../helpers/policy.php';
require_once __DIR__ . '/../helpers/identity.php';
require_once __DIR__ . '/../helpers/sms.php';
function handle_employees(string $path, string $method, array $body): void {
    $pdo      = getDB();
    employees_apply_due_promotions($pdo);
    $segments = explode('/', $path);
    // segments[0] = 'employees', segments[1] = id or 'me'
    $sub = $segments[1] ?? '';

    // GET /employees/shared-in  — people other companies of the group share with this one (basic details, read-only).
    // Kept apart from the normal list on purpose: pickers (payroll, leaves, department heads...) must only offer OWN people.
    if ($sub === 'shared-in' && $method === 'GET') { require_hr(); employees_shared_in($pdo); return; }

    // GET /employees/me  — current user's employee record
    if ($sub === 'me' && $method === 'GET') {
        employees_get_me(me(), $pdo);
        return;
    }

    // Invitations for everybody (HR): how many are ready, and send them
    if ($sub === 'invite-status' && $method === 'GET') { require_hr(); employees_invite_status($pdo); }
    if ($sub === 'invite-all' && $method === 'POST')   { require_hr(); employees_invite_all($body, $pdo); }

    $id = ($sub !== '' && is_numeric($sub)) ? intval($sub) : null;

    // POST /employees/{id}/invite — one-time code so the employee can activate / reset their app account
    if ($id !== null && ($segments[2] ?? '') === 'invite') {
        if ($method !== 'POST') error_response('Method not allowed', 405);
        require_hr();
        employees_invite($id, $pdo, $body);
        return;
    }

    // PUT /employees/{id}/attendance-access   GET /employees/{id}/attendance-attempts   (HR)
    if ($id !== null && ($segments[2] ?? '') === 'attendance-access' && $method === 'PUT') { require_hr(); employees_attendance_access($id, $body, $pdo); return; }
    if ($id !== null && ($segments[2] ?? '') === 'attendance-attempts' && $method === 'GET') { require_hr(); employees_attendance_attempts($id, $pdo); return; }

    if ($id !== null && isset($segments[2])) {
        $action = $segments[2];
        if ($action === 'promotions' && $method === 'GET') {
            if (!is_hr() && $id !== own_employee_id()) error_response('Forbidden. Insufficient permissions.', 403);
            employees_promotions($id, $pdo);
            return;
        }
        require_hr();
        if ($action === 'promote'   && $method === 'POST') { employees_promote($id, $body, $pdo); return; }
        if ($action === 'terminate' && $method === 'POST') { employees_terminate($id, $body, $pdo); return; }
        if ($action === 'reinstate' && $method === 'POST') { employees_reinstate($id, $pdo); return; }
        error_response('Not found', 404);
    }

    if ($id !== null) {
        switch ($method) {
            case 'GET':    employees_get_one($id, $pdo); break;
            case 'PUT':    require_hr(); employees_update($id, $body, $pdo); break;
            case 'DELETE': require_hr(); employees_delete($id, $pdo); break;
            default:       error_response('Method not allowed', 405);
        }
    } else {
        switch ($method) {
            case 'GET':    employees_list($pdo); break;
            case 'POST':   require_hr(); employees_create($body, $pdo); break;
            default:       error_response('Method not allowed', 405);
        }
    }
}

/** How this person records attendance: the company rules, one chosen rule (another place), or no place check; and whether HR blocked them. */
function employees_attendance_access(int $id, array $body, PDO $pdo): void {
    $emp = employees_fetch($id, $pdo);
    if (!$emp) error_response('Employee not found', 404);
    $mode = (string)($body['attendance_mode'] ?? $emp['attendance_mode'] ?? 'company');
    if (!in_array($mode, ['company', 'rule', 'free'], true)) error_response('attendance_mode must be company, rule or free', 422);
    $ruleId = null;
    if ($mode === 'rule') {
        $ruleId = (int)($body['attendance_rule_id'] ?? 0);
        $chk = $pdo->prepare("SELECT 1 FROM attendance_rules WHERE id = ? AND company_id = ?");
        $chk->execute([$ruleId, cid()]);
        if (!$chk->fetchColumn()) error_response('Choose one of the attendance rules of this company', 422);
    }
    $blocked = array_key_exists('attendance_blocked', $body) ? (empty($body['attendance_blocked']) ? 0 : 1) : (int)$emp['attendance_blocked'];
    $reason = $blocked ? mb_substr(trim((string)($body['attendance_block_reason'] ?? $emp['attendance_block_reason'] ?? '')), 0, 250) : null;
    $when = $blocked ? ((int)$emp['attendance_blocked'] ? $emp['attendance_blocked_at'] : att_now($pdo)->format('Y-m-d H:i:s')) : null;
    $pdo->prepare("UPDATE employees SET attendance_mode = ?, attendance_rule_id = ?, attendance_blocked = ?, attendance_block_reason = ?, attendance_blocked_at = ? WHERE id = ? AND company_id = ?")
        ->execute([$mode, $ruleId, $blocked, $reason === '' ? null : $reason, $when, $id, cid()]);
    audit($pdo, 'attendance_access', 'employee', $id, ['mode' => $mode, 'rule' => $ruleId, 'blocked' => $blocked, 'reason' => $reason]);
    json_response(['success' => true, 'data' => employees_public(employees_fetch($id, $pdo))]);
}

function employees_attendance_attempts(int $id, PDO $pdo): void {
    if (!employees_fetch($id, $pdo)) error_response('Employee not found', 404);
    $s = $pdo->prepare("SELECT id, action, lat, lng, distance_m, message, created_at FROM attendance_attempts WHERE company_id = ? AND employee_id = ? ORDER BY id DESC LIMIT 20");
    $s->execute([cid(), $id]);
    json_response(['success' => true, 'data' => $s->fetchAll()]);
}

function employees_select(): string {
    return "SELECT e.*, d.name AS department_name, s.name AS shift_name,
                   CONCAT(m.first_name, ' ', m.last_name) AS manager_name,
                   EXISTS(SELECT 1 FROM users ux WHERE ux.employee_id = e.id AND ux.role = 'employee' AND ux.status = 'active') AS has_account,
                   (SELECT MIN(uf.created_at) FROM users uf WHERE uf.employee_id = e.id AND uf.role = 'employee') AS first_signin_at
            FROM employees e
            LEFT JOIN departments d ON d.id = e.department_id
            LEFT JOIN shifts s ON s.id = e.shift_id
            LEFT JOIN employees m ON m.id = e.manager_id";
}

/** Lower-case, no accents/tatweel, one spelling of the Arabic letters that people type differently. */
function employees_search_norm(string $t): string {
    $t = mb_strtolower(trim($t), 'UTF-8');
    $t = preg_replace('/[\x{064B}-\x{065F}\x{0670}\x{0640}]/u', '', $t);
    $t = strtr($t, ['أ' => 'ا', 'إ' => 'ا', 'آ' => 'ا', 'ٱ' => 'ا', 'ى' => 'ي', 'ة' => 'ه', 'ؤ' => 'و', 'ئ' => 'ي']);
    $t = strtr($t, ['٠' => '0', '١' => '1', '٢' => '2', '٣' => '3', '٤' => '4', '٥' => '5', '٦' => '6', '٧' => '7', '٨' => '8', '٩' => '9']);
    return preg_replace('/\s+/u', ' ', $t);
}

/** Does this employee match the (already normalised) search text? Name, e-mail, job, department, nationality, ID, IBAN, mobile. */
function employees_row_matches(array $r, string $needle, string $digits): bool {
    $hay = employees_search_norm(implode(' ', [$r['first_name'] ?? '', $r['last_name'] ?? '', $r['email'] ?? '', $r['position'] ?? '', $r['department_name'] ?? '',
                                               $r['nationality'] ?? '', $r['id_number'] ?? '', $r['bank_iban'] ?? '', $r['phone'] ?? '']));
    if (str_contains($hay, $needle)) return true;
    return strlen($digits) >= 3 && str_contains(preg_replace('/\D+/', '', (string)($r['phone'] ?? '')), $digits);
}

/** OWNER ONLY - GET /group/search?q=  : the same search, over every company of the group, each result tagged with its company. */
function employees_search_all_companies(PDO $pdo, int $groupId): void {
    if (!group_is_owner($pdo, (int)me()['id'])) error_response('Forbidden. Only the owner can search all companies.', 403);
    $needle = employees_search_norm((string)($_GET['q'] ?? ''));
    if (mb_strlen($needle, 'UTF-8') < 2) json_response(['success' => true, 'data' => []]);
    $digits = preg_replace('/\D+/', '', $needle);
    $activeId = (int)cid();

    $cs = $pdo->prepare("SELECT id, name FROM companies WHERE group_id = ? AND status = 'active' ORDER BY (id = ?) DESC, name");
    $cs->execute([$groupId, $activeId]);
    $out = [];
    foreach ($cs->fetchAll() as $c) {
        $st = $pdo->prepare(employees_select() . " WHERE e.company_id = ? AND e.status != 'inactive' ORDER BY e.first_name, e.last_name");
        $st->execute([(int)$c['id']]);
        $n = 0;
        foreach ($st->fetchAll() as $row) {
            $r = employees_public($row);
            if (!employees_row_matches($r, $needle, $digits)) continue;
            $out[] = [
                'id' => (int)$r['id'], 'first_name' => $r['first_name'], 'last_name' => $r['last_name'], 'position' => $r['position'] ?? null,
                'department_name' => $r['department_name'] ?? null, 'id_number' => $r['id_number'] ?? null,
                'company_id' => (int)$c['id'], 'company_name' => $c['name'], 'is_current' => (int)$c['id'] === $activeId,
            ];
            if (++$n >= 6) break;
        }
        if (count($out) >= 30) break;
    }
    json_response(['success' => true, 'data' => $out]);
}

function employees_shared_in(PDO $pdo): void {
    $sh = $pdo->prepare(
        "SELECT e.id, e.first_name, e.last_name, e.position, e.email, e.phone, e.avatar, e.status, e.department_id, d.name AS department_name,
                e.company_id, c.name AS shared_from
         FROM group_shares g JOIN employees e ON e.id = g.item_id AND e.company_id = g.source_company_id
         JOIN companies c ON c.id = e.company_id LEFT JOIN departments d ON d.id = e.department_id
         WHERE g.kind = 'employee' AND g.target_company_id = ? AND e.status != 'inactive' ORDER BY e.first_name, e.last_name");
    $sh->execute([cid()]);
    $rows = [];
    $needle = employees_search_norm((string)($_GET['q'] ?? ''));
    $digits = preg_replace('/\D+/', '', $needle);
    foreach ($sh->fetchAll() as $r) {
        if ($needle !== '' && !employees_row_matches($r, $needle, $digits)) continue;
        $r['email'] = email_public($r['email'] ?? '');
        $r['shared'] = true;
        $r['read_only'] = true;
        $r['missing'] = [];
        $r['incomplete'] = false;
        $r['has_account'] = false;
        $r['invite_ready'] = false;
        $rows[] = $r;
    }
    json_response(['success' => true, 'data' => $rows]);
}

function employees_list(PDO $pdo): void {
    require_hr();
    $where  = ['e.company_id = ?'];
    $params = [cid()];

    if (!empty($_GET['department_id'])) {
        $where[]  = 'e.department_id = ?';
        $params[] = intval($_GET['department_id']);
    }
    if (!empty($_GET['status'])) {
        $where[]  = 'e.status = ?';
        $params[] = $_GET['status'];
    }

    $stmt = $pdo->prepare(employees_select() . " WHERE " . implode(' AND ', $where) . " ORDER BY e.first_name, e.last_name");
    $stmt->execute($params);

    $rows = array_map('employees_public', $stmt->fetchAll());
    $counts = group_share_counts($pdo, 'employee');
    foreach ($rows as &$own) $own['shared_count'] = (int)($counts[$own['id']] ?? 0);
    unset($own);
    // Search: Arabic spelling variants (أ/إ/آ/ا, ى/ي, ة/ه, accents) and numbers (ID, mobile, bank account) all match
    $needle = employees_search_norm((string)($_GET['q'] ?? ''));
    if ($needle !== '') {
        $digits = preg_replace('/\D+/', '', $needle);
        $rows = array_values(array_filter($rows, fn($r) => employees_row_matches($r, $needle, $digits)));
    }
    if (!empty($_GET['incomplete'])) $rows = array_values(array_filter($rows, fn($r) => $r['incomplete']));
    if (!empty($_GET['no_account'])) $rows = array_values(array_filter($rows, fn($r) => !$r['has_account']));
    json_response(['success' => true, 'data' => $rows]);
}


/** What HR still has to fill in before this person can really work (and be invited). */
function employees_missing(array $e): array {
    $m = [];
    if (!email_is_real($e['email'] ?? '') && !phone_valid($e['phone'] ?? '')) $m[] = 'contact';
    if (empty($e['department_id'])) $m[] = 'department';
    if (trim((string)($e['position'] ?? '')) === '') $m[] = 'position';
    if (empty($e['start_date'])) $m[] = 'start_date';
    if (!isset($e['salary']) || $e['salary'] === '' || (float)$e['salary'] <= 0) $m[] = 'salary';
    return $m;
}

/** An employee as the apps see it: no internal placeholder e-mail, what is missing, whether an invitation can go out. */
function employees_public(array $e): array {
    $missing = employees_missing($e);
    $hasMail = email_is_real($e['email'] ?? '');
    $e['has_email'] = $hasMail;
    $e['has_phone'] = phone_valid($e['phone'] ?? '');
    $e['email'] = email_public($e['email'] ?? '');
    $e['missing'] = $missing;
    $e['incomplete'] = count($missing) > 0;
    $e['has_account'] = !empty($e['has_account']);
    $e['invite_ready'] = !$e['has_account'] && ($e['status'] ?? '') !== 'inactive' && ($hasMail || $e['has_phone']);
    unset($e['phone_key']);
    return $e;
}

/**
 * Work status follows the first digit of the ID: 2 = residence, HR must say whose sponsorship (own_sponsor | other_sponsor);
 * any other first digit = irregular, no sponsor. No ID yet = whatever was sent (or nothing).
 */
function employees_work_status(?string $idNumber, $given): ?string {
    $id = trim((string)$idNumber);
    $given = $given === null ? null : (string)$given;
    if ($id === '') return in_array($given, ['own_sponsor', 'other_sponsor', 'irregular'], true) ? $given : null;
    if ($id[0] !== '2') return 'irregular';
    if (!in_array($given, ['own_sponsor', 'other_sponsor'], true)) error_response('Choose the work status: on our sponsorship or on another sponsor', 422);
    return $given;
}

/** Fields of the residence / ID sheet, in the order the forms show them. */
function employees_extra_fields(): array {
    return ['nationality', 'id_number', 'work_status', 'bank_iban', 'iqama_expiry', 'iqama_renew_months', 'import_notes'];
}

/** Validate the optional contact fields of a request. Returns [email|null, phone|null]; stops with a clear message otherwise. */
function employees_contact(PDO $pdo, array $body, int $exceptId = 0): array {
    $email = array_key_exists('email', $body) ? strtolower(trim((string)$body['email'])) : null;
    $phone = array_key_exists('phone', $body) ? trim((string)$body['phone']) : null;
    if ($exceptId > 0) {            // a value that did not change is never re-checked (old records may hold odd numbers)
        $cur = $pdo->prepare("SELECT email, phone FROM employees WHERE id = ? AND company_id = ?");
        $cur->execute([$exceptId, cid()]);
        $was = $cur->fetch() ?: [];
        $sameMail = $email !== null && $email !== '' && strtolower((string)($was['email'] ?? '')) === $email;
        $samePhone = $phone !== null && $phone !== '' && trim((string)($was['phone'] ?? '')) === $phone;
    } else { $sameMail = $samePhone = false; }
    if ($email !== null && $email !== '' && !$sameMail) {
        if (!filter_var($email, FILTER_VALIDATE_EMAIL) || str_ends_with($email, '@' . NO_EMAIL_DOMAIN)) error_response('Invalid email address', 422);
        $dup = $pdo->prepare("SELECT id FROM employees WHERE email = ? AND id != ? LIMIT 1");
        $dup->execute([$email, $exceptId]);
        if ($dup->fetch()) error_response('An employee with this email already exists', 409);
    }
    if ($phone !== null && $phone !== '' && !$samePhone) {
        if (!phone_valid($phone)) error_response('The mobile number is not valid. Enter it with the country code, for example +966 5x xxx xxxx.', 422);
        $who = phone_taken($pdo, $phone, $exceptId);
        if ($who !== null) error_response("This mobile number is already used by $who", 409);
    }
    return [$email === '' ? null : $email, $phone === '' ? null : $phone];
}

/** Which way an invitation goes: [channel|null, error|null]. $via: auto (e-mail first, then SMS) | email | sms. */
function employees_pick_channel(array $e, string $via): array {
    $hasMail = email_is_real($e['email'] ?? '');
    $hasPhone = phone_valid($e['phone'] ?? '');
    if ($via === 'email') return $hasMail ? ['email', null] : [null, 'This employee has no e-mail address.'];
    if ($via === 'sms')   return $hasPhone ? ['sms', null] : [null, 'This employee has no mobile number.'];
    if ($hasMail) return ['email', null];
    if ($hasPhone) return ['sms', null];
    return [null, 'This employee has no e-mail address or mobile number yet.'];
}

/** Send the code. @return array{0: bool, 1: ?string} */
function employees_send_invite(PDO $pdo, array $e, string $channel, string $code, string $purpose, int $days): array {
    $company = (string)(company_get($pdo, cid())['name'] ?? 'Al Anad HR');
    $valid = $purpose === 'activate' ? "$days days" : 'a day';
    if ($channel === 'email') {
        require_once __DIR__ . '/../helpers/mailer.php';
        $ok = mail_send_code((string)$e['email'], $company, $purpose, $code, $valid, (string)$e['email']);
        return [$ok, $ok ? null : (mail_last_error() ?: 'The e-mail could not be sent.')];
    }
    $text = $purpose === 'activate' ? sms_invite_text($company, (string)$e['phone'], $code, $valid) : sms_reset_text($company, $code, $valid);
    return sms_send($e['phone'], $text);
}

function employees_has_account(PDO $pdo, int $id): bool {
    $u = $pdo->prepare("SELECT 1 FROM users WHERE employee_id = ? AND company_id = ? AND role = 'employee' LIMIT 1");
    $u->execute([$id, cid()]);
    return (bool)$u->fetchColumn();
}

/** Create the one-time code and (when asked) send it. Returns the invitation result the apps show. */
function employees_do_invite(PDO $pdo, array $employee, string $via): array {
    $hasAccount = employees_has_account($pdo, (int)$employee['id']);
    $purpose = $hasAccount ? 'reset' : 'activate';
    $days = $hasAccount ? 1 : 7;
    $code = invitation_create($pdo, (int)$employee['id'], $purpose, $days);
    $channel = null; $sent = null; $error = null;
    if ($via !== 'none') {
        [$channel, $error] = employees_pick_channel($employee, $via);
        if ($channel !== null) {
            [$sent, $error] = employees_send_invite($pdo, $employee, $channel, $code, $purpose, $days);
            if ($sent) $pdo->prepare("UPDATE employees SET invited_at = ?, invited_via = ? WHERE id = ? AND company_id = ?")->execute([att_now($pdo)->format('Y-m-d H:i:s'), $channel, $employee['id'], cid()]);
        } else {
            $sent = false;
        }
    }
    return [
        'employee_id' => (int)$employee['id'], 'email' => email_public($employee['email']), 'phone' => $employee['phone'], 'purpose' => $purpose, 'code' => $code,
        'expires_in_days' => $days, 'channel' => $channel, 'sent' => $sent, 'error' => $error,
        'emailed' => $channel === 'email' ? $sent : null,      // older apps
        'username' => email_is_real($employee['email']) ? $employee['email'] : (string)$employee['phone'],
    ];
}

function employees_invite_status(PDO $pdo): void {
    require_once __DIR__ . '/../helpers/mailer.php';
    $s = $pdo->prepare(employees_select() . " WHERE e.company_id = ? AND e.status != 'inactive'");
    $s->execute([cid()]);
    $c = ['pending' => 0, 'ready' => 0, 'by_email' => 0, 'by_sms_only' => 0, 'no_contact' => 0, 'already_invited' => 0, 'with_account' => 0, 'incomplete' => 0, 'total' => 0];
    foreach ($s->fetchAll() as $row) {
        $e = employees_public($row);
        $c['total']++;
        if ($e['incomplete']) $c['incomplete']++;
        if ($e['has_account']) { $c['with_account']++; continue; }
        $c['pending']++;
        if (!$e['invite_ready']) { $c['no_contact']++; continue; }
        $c['ready']++;
        if ($e['has_email']) $c['by_email']++; else $c['by_sms_only']++;
        if (!empty($e['invited_at'])) $c['already_invited']++;
    }
    json_response(['success' => true, 'data' => ['summary' => $c, 'channels' => ['email' => true, 'smtp' => mail_smtp_configured(), 'sms' => sms_configured()]]]);
}

/** Send every waiting employee their invitation (HR pressed the button and confirmed). */
function employees_invite_all(array $body, PDO $pdo): void {
    if (empty($body['confirm'])) error_response('Confirm that the invitations should be sent now', 422);
    $via = in_array($body['send_via'] ?? 'auto', ['auto', 'email', 'sms'], true) ? (string)($body['send_via'] ?? 'auto') : 'auto';
    $includeInvited = !empty($body['include_invited']);
    @set_time_limit(300);
    $s = $pdo->prepare(employees_select() . " WHERE e.company_id = ? AND e.status != 'inactive' ORDER BY e.id");
    $s->execute([cid()]);
    $out = ['sent' => 0, 'failed' => [], 'skipped_no_contact' => 0, 'skipped_already_invited' => 0, 'skipped_has_account' => 0];
    foreach ($s->fetchAll() as $row) {
        $e = employees_public($row);
        if ($e['has_account']) { $out['skipped_has_account']++; continue; }
        if (!$e['invite_ready']) { $out['skipped_no_contact']++; continue; }
        if (!$includeInvited && !empty($row['invited_at'])) { $out['skipped_already_invited']++; continue; }
        $r = employees_do_invite($pdo, $row, $via);
        if ($r['sent']) $out['sent']++;
        else if (count($out['failed']) < 50) $out['failed'][] = ['id' => (int)$row['id'], 'name' => trim($row['first_name'] . ' ' . $row['last_name']), 'error' => $r['error'] ?: 'Not sent'];
    }
    audit($pdo, 'invite_all', 'employee', null, ['sent' => $out['sent'], 'failed' => count($out['failed'])]);
    json_response(['success' => true, 'data' => $out]);
}

function employees_fetch(int $id, PDO $pdo): ?array {
    $stmt = $pdo->prepare(employees_select() . " WHERE e.id = ? AND e.company_id = ?");
    $stmt->execute([$id, cid()]);
    $employee = $stmt->fetch();
    return $employee ?: null;
}

function employees_get_one(int $id, PDO $pdo): void {
    $employee = employees_fetch($id, $pdo);
    if (!$employee) {
        error_response('Employee not found', 404);
    }
    json_response(['success' => true, 'data' => employees_public($employee)]);
}

function employees_get_me(array $currentUser, PDO $pdo): void {
    if (!$currentUser['employee_id']) {
        error_response('No employee record linked to this account', 404);
    }
    $employee = employees_fetch((int)$currentUser['employee_id'], $pdo);
    if (!$employee) {
        error_response('Employee not found', 404);
    }
    // Attach the assigned shift so the mobile app can enforce shift hours
    if (!empty($employee['shift_id'])) {
        $s = $pdo->prepare("SELECT id, name, start_time, end_time, color, days FROM shifts WHERE id = ? AND company_id = ?");
        $s->execute([$employee['shift_id'], cid()]);
        $employee['shift'] = $s->fetch() ?: null;
    }
    json_response(['success' => true, 'data' => employees_public($employee)]);
}

/** Validate optional foreign keys so an employee can never point into another company. */
function employees_validate_refs(PDO $pdo, array $body): void {
    foreach (['department_id' => 'departments', 'shift_id' => 'shifts', 'manager_id' => 'employees'] as $field => $table) {
        if (empty($body[$field])) continue;
        $ok = $field === 'department_id' ? department_visible($pdo, int_or_null($body[$field])) : in_company($pdo, $table, int_or_null($body[$field]));
        if (!$ok) error_response("Invalid $field", 422);
    }
}

function employees_create(array $body, PDO $pdo): void {
    $firstName = trim($body['first_name'] ?? '');
    $lastName  = trim($body['last_name'] ?? '');

    if ($firstName === '' || $lastName === '') {
        error_response('first_name and last_name are required');
    }
    employees_validate_refs($pdo, $body);
    require_once __DIR__ . '/../helpers/contracts.php';
    $contract = contract_fields($body);
    [$email, $phone] = employees_contact($pdo, $body);          // either one, both, or none yet (HR completes it later)
    $storedEmail = $email ?? placeholder_email($pdo);
    $extra = [];
    foreach (employees_extra_fields() as $f) {
        $v = array_key_exists($f, $body) && $body[$f] !== '' ? $body[$f] : null;
        if ($f === 'iqama_expiry' && $v !== null && !preg_match('/^\d{4}-\d{2}-\d{2}$/', (string)$v)) error_response('Residence expiry must be YYYY-MM-DD', 422);
        $extra[$f] = $v === null ? null : ($f === 'iqama_renew_months' ? max(1, min(240, (int)$v)) : mb_substr((string)$v, 0, $f === 'import_notes' ? 2000 : 60));
    }

    $extra['work_status'] = employees_work_status($extra['id_number'], $extra['work_status']);
    $stmt = $pdo->prepare(
        "INSERT INTO employees
            (company_id, first_name, last_name, email, phone, phone_key, position, department_id, shift_id, manager_id,
             status, start_date, salary, avatar, birth_date, gender, address, emergency_name, emergency_phone,
             nationality, id_number, work_status, bank_iban, iqama_expiry, iqama_renew_months, import_notes)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    );
    $stmt->execute([
        cid(),
        $firstName,
        $lastName,
        $storedEmail,
        $phone,
        phone_key($phone),
        $body['position']       ?? null,
        int_or_null($body['department_id'] ?? null),
        int_or_null($body['shift_id'] ?? null),
        int_or_null($body['manager_id'] ?? null),
        $body['status']         ?? 'active',
        !empty($body['start_date']) ? $body['start_date'] : date('Y-m-d'),
        isset($body['salary']) && $body['salary'] !== '' ? floatval($body['salary']) : null,
        $body['avatar']         ?? null,
        !empty($body['birth_date']) ? $body['birth_date'] : null,
        $body['gender']         ?? null,
        $body['address']        ?? null,
        $body['emergency_name'] ?? null,
        $body['emergency_phone'] ?? null,
        $extra['nationality'], $extra['id_number'], $extra['work_status'], $extra['bank_iban'], $extra['iqama_expiry'], $extra['iqama_renew_months'], $extra['import_notes'],
    ]);

    $newId = (int)$pdo->lastInsertId();
    if ($contract) {
        $set = []; $args = [];
        foreach ($contract as $k => $v) { $set[] = "$k = ?"; $args[] = $v; }
        $args[] = $newId; $args[] = cid();
        $pdo->prepare("UPDATE employees SET " . implode(', ', $set) . " WHERE id = ? AND company_id = ?")->execute($args);
        contracts_reset($pdo);
    }
    employees_default_manager($pdo, $newId);
    audit($pdo, 'create', 'employee', $newId, ['name' => "$firstName $lastName"]);
    notify_hr($pdo, 'employee_added', 'New employee added', "$firstName $lastName joined the team.", ['employee_id' => $newId], (int)me()['id']);

    // Give the new hire their onboarding checklist (never blocks creation)
    try { require_once __DIR__ . '/onboarding.php'; onboarding_start($pdo, $newId, false); } catch (Throwable $e) { error_log('onboarding: ' . $e->getMessage()); }

    // The one-time code they need to create their password; sent only when HR chooses to (e-mail or SMS)
    $row = employees_fetch($newId, $pdo);
    $via = (string)($body['send_via'] ?? (!empty($body['send_email']) ? 'auto' : 'none'));
    if (!in_array($via, ['none', 'auto', 'email', 'sms'], true)) $via = 'none';
    $invite = employees_do_invite($pdo, $row, $via);
    $employee = employees_public(employees_fetch($newId, $pdo));
    $employee['invite_code'] = $invite['code'];
    $employee['invite'] = $invite;
    $employee['emailed'] = $invite['emailed'];
    json_response(['success' => true, 'data' => $employee], 201);
}

function employees_invite(int $id, PDO $pdo, array $body = []): void {
    $employee = employees_fetch($id, $pdo);
    if (!$employee) error_response('Employee not found', 404);
    if ($employee['status'] === 'inactive') error_response('This employee is inactive', 422);
    $via = (string)($body['send_via'] ?? (!empty($body['send_email']) ? 'auto' : 'none'));
    if (!in_array($via, ['none', 'auto', 'email', 'sms'], true)) $via = 'none';
    json_response(['success' => true, 'data' => employees_do_invite($pdo, $employee, $via)]);
}

function employees_update(int $id, array $body, PDO $pdo): void {
    if (!in_company($pdo, 'employees', $id)) {
        error_response('Employee not found', 404);
    }
    employees_validate_refs($pdo, $body);
    if (isset($body['manager_id']) && (int)$body['manager_id'] === $id) {
        error_response('An employee cannot be their own manager', 422);
    }

    $fields = [];
    $params = [];

    $updatable = [
        'first_name', 'last_name', 'phone', 'position', 'status', 'start_date', 'avatar',
        'birth_date', 'gender', 'address', 'emergency_name', 'emergency_phone',
        'nationality', 'id_number', 'work_status', 'bank_iban', 'iqama_expiry', 'iqama_renew_months', 'import_notes',
    ];
    if (array_key_exists('id_number', $body) || array_key_exists('work_status', $body)) {
        $idNow = array_key_exists('id_number', $body) ? trim((string)$body['id_number']) : (string)(employees_fetch($id, $pdo)['id_number'] ?? '');
        $body['work_status'] = employees_work_status($idNow === '' ? null : $idNow, ($body['work_status'] ?? '') === '' ? null : $body['work_status']);
    }
    if (!empty($body['iqama_expiry']) && !preg_match('/^\d{4}-\d{2}-\d{2}$/', (string)$body['iqama_expiry'])) error_response('Residence expiry must be YYYY-MM-DD', 422);
    $before = employees_fetch($id, $pdo);
    foreach ($updatable as $field) {
        if ($field === 'phone') continue;                       // handled below (checked, and the sign-in key is kept in step)
        if (array_key_exists($field, $body)) {
            $fields[] = "$field = ?";
            $params[]  = $body[$field] === '' ? null : $body[$field];
        }
    }
    if (array_key_exists('email', $body) || array_key_exists('phone', $body)) {
        [$email, $phone] = employees_contact($pdo, $body, $id);
        if (array_key_exists('email', $body)) {
            if ($email === null) {
                if (employees_has_account($pdo, $id)) error_response('This person already has an account: the e-mail address cannot be removed', 422);
                if (email_is_real($before['email'] ?? '')) { $fields[] = 'email = ?'; $params[] = placeholder_email($pdo); }
            } else {
                $fields[] = 'email = ?';
                $params[]  = $email;
            }
        }
        if (array_key_exists('phone', $body)) {
            $fields[] = 'phone = ?'; $params[] = $phone;
            $fields[] = 'phone_key = ?'; $params[] = phone_key($phone);
        }
    }
    foreach (['department_id', 'shift_id', 'manager_id'] as $fk) {
        if (array_key_exists($fk, $body)) {
            $fields[] = "$fk = ?";
            $params[]  = int_or_null($body[$fk]);
        }
    }
    require_once __DIR__ . '/../helpers/contracts.php';
    $cur = $pdo->prepare("SELECT * FROM employees WHERE id = ? AND company_id = ?");
    $cur->execute([$id, cid()]);
    $contract = contract_fields($body, $cur->fetch() ?: null);
    foreach ($contract as $k => $v) { $fields[] = "$k = ?"; $params[] = $v; }
    if ($contract) contracts_reset($pdo);
    if (array_key_exists('salary', $body)) {
        $fields[] = 'salary = ?';
        $params[]  = $body['salary'] === '' || $body['salary'] === null ? null : floatval($body['salary']);
    }

    if (empty($fields)) {
        error_response('No fields to update');
    }

    $params[] = $id;
    $params[] = cid();
    $pdo->prepare("UPDATE employees SET " . implode(', ', $fields) . " WHERE id = ? AND company_id = ?")->execute($params);

    if (array_key_exists('department_id', $body) && !array_key_exists('manager_id', $body)) employees_default_manager($pdo, $id);
    audit($pdo, 'update', 'employee', $id, array_diff_key($body, ['avatar' => 1]));
    if (array_key_exists('phone', $body)) {
        $pdo->prepare("UPDATE users SET phone = ?, phone_key = ? WHERE employee_id = ? AND company_id = ? AND role = 'employee'")
            ->execute([trim((string)$body['phone']) === '' ? null : trim((string)$body['phone']), phone_key($body['phone']), $id, cid()]);
    }

    // A deactivated employee can no longer sign in
    if (isset($body['status']) && $body['status'] === 'inactive') {
        $pdo->prepare("UPDATE users SET status = 'disabled' WHERE employee_id = ? AND company_id = ? AND role = 'employee'")->execute([$id, cid()]);
    } elseif (isset($body['status']) && in_array($body['status'], ['active', 'on_leave'], true)) {
        $pdo->prepare("UPDATE users SET status = 'active' WHERE employee_id = ? AND company_id = ? AND role = 'employee' AND status = 'disabled'")->execute([$id, cid()]);
    }

    employees_get_one($id, $pdo);
}

function employees_delete(int $id, PDO $pdo): void {
    if (!in_company($pdo, 'employees', $id)) {
        error_response('Employee not found', 404);
    }

    employees_do_terminate($id, null, null, $pdo);
    json_response(['success' => true, 'message' => 'Employee deactivated']);
}


// ------------------------------------------------------------ career: promotions, exit

/** A member without a manager reports to the head of their department. */
function employees_default_manager(PDO $pdo, int $employeeId): void {
    $pdo->prepare(
        "UPDATE employees e JOIN departments d ON d.id = e.department_id AND d.company_id = e.company_id
         SET e.manager_id = d.head_employee_id
         WHERE e.id = ? AND e.company_id = ? AND e.manager_id IS NULL AND d.head_employee_id IS NOT NULL AND d.head_employee_id != e.id"
    )->execute([$employeeId, cid()]);
}

function employees_promotion_labels(): array {
    return ['promotion' => 'Promotion', 'raise' => 'Salary raise', 'transfer' => 'Transfer', 'demotion' => 'Role change'];
}

function employees_promotions(int $id, PDO $pdo): void {
    if (!employee_in_company($pdo, $id)) error_response('Employee not found', 404);
    $s = $pdo->prepare(
        "SELECT p.*, fd.name AS from_department_name, td.name AS to_department_name, u.name AS created_by_name
         FROM promotions p
         LEFT JOIN departments fd ON fd.id = p.from_department_id
         LEFT JOIN departments td ON td.id = p.to_department_id
         LEFT JOIN users u ON u.id = p.created_by
         WHERE p.company_id = ? AND p.employee_id = ? ORDER BY p.effective_date DESC, p.id DESC"
    );
    $s->execute([cid(), $id]);
    json_response(['success' => true, 'data' => $s->fetchAll()]);
}

/** Apply promotions/raises/transfers whose effective date has arrived. */
function employees_apply_due_promotions(PDO $pdo): void {
    if (empty($GLOBALS['HR_USER'])) return;
    $today = att_now($pdo)->format('Y-m-d');
    $s = $pdo->prepare("SELECT * FROM promotions WHERE company_id = ? AND applied = 0 AND effective_date <= ? LIMIT 50");
    $s->execute([cid(), $today]);
    foreach ($s->fetchAll() as $p) employees_apply_promotion($pdo, $p);
}

function employees_apply_promotion(PDO $pdo, array $p): void {
    $e = $pdo->prepare("SELECT position, salary, department_id FROM employees WHERE id = ? AND company_id = ?");
    $e->execute([$p['employee_id'], cid()]);
    $cur = $e->fetch();
    if (!$cur) return;
    $f = []; $a = [];
    if ($p['to_position'] !== null)      { $f[] = 'position = ?';      $a[] = $p['to_position']; }
    if ($p['to_salary'] !== null)        { $f[] = 'salary = ?';        $a[] = $p['to_salary']; }
    if ($p['to_department_id'] !== null) { $f[] = 'department_id = ?'; $a[] = $p['to_department_id']; }
    if ($f) {
        $a[] = $p['employee_id']; $a[] = cid();
        $pdo->prepare("UPDATE employees SET " . implode(', ', $f) . " WHERE id = ? AND company_id = ?")->execute($a);
        if ($p['to_department_id'] !== null) {
            $pdo->prepare("UPDATE employees SET manager_id = NULL WHERE id = ? AND company_id = ?")->execute([$p['employee_id'], cid()]);
            employees_default_manager($pdo, (int)$p['employee_id']);
        }
    }
    $pdo->prepare("UPDATE promotions SET applied = 1, from_position = ?, from_salary = ?, from_department_id = ? WHERE id = ? AND company_id = ?")
        ->execute([$cur['position'], $cur['salary'], $cur['department_id'], $p['id'], cid()]);

    $msg = [
        'promotion' => 'Congratulations! You have been promoted' . ($p['to_position'] ? ' to ' . $p['to_position'] : '') . '.',
        'raise'     => 'Good news: your salary has been updated.',
        'transfer'  => 'You have been transferred to a new department.',
        'demotion'  => 'Your role has been updated' . ($p['to_position'] ? ' to ' . $p['to_position'] : '') . '.',
    ][$p['type']] ?? 'Your job details were updated.';
    notify_employee($pdo, (int)$p['employee_id'], 'promotion', employees_promotion_labels()[$p['type']] ?? 'Update', $msg, ['promotion_id' => (int)$p['id']]);
}

function employees_promote(int $id, array $body, PDO $pdo): void {
    $emp = employees_fetch($id, $pdo);
    if (!$emp) error_response('Employee not found', 404);
    if ($emp['status'] === 'inactive') error_response('This employee is inactive', 422);

    $type = (string)($body['type'] ?? 'promotion');
    if (!isset(employees_promotion_labels()[$type])) error_response('Invalid type', 422);
    $position = isset($body['position']) && trim((string)$body['position']) !== '' ? trim((string)$body['position']) : null;
    $salary   = isset($body['salary']) && $body['salary'] !== '' ? floatval($body['salary']) : null;
    $dept     = int_or_null($body['department_id'] ?? null);
    if ($dept !== null && !department_visible($pdo, $dept)) error_response('Invalid department', 422);
    if ($salary !== null && $salary < 0) error_response('Salary cannot be negative', 422);
    if ($position === null && $salary === null && $dept === null) error_response('Enter a new position, salary or department', 422);

    $date = !empty($body['effective_date']) ? (string)$body['effective_date'] : att_now($pdo)->format('Y-m-d');
    $dd = DateTime::createFromFormat('Y-m-d', $date);
    if (!$dd || $dd->format('Y-m-d') !== $date) error_response('Date must be YYYY-MM-DD', 422);

    $pdo->prepare(
        "INSERT INTO promotions (company_id, employee_id, type, to_position, to_salary, to_department_id, effective_date, applied, note, created_by)
         VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?)"
    )->execute([cid(), $id, $type, $position, $salary, $dept, $date, isset($body['note']) ? mb_substr((string)$body['note'], 0, 1000) : null, (int)me()['id']]);
    $pid = (int)$pdo->lastInsertId();
    audit($pdo, $type, 'employee', $id, ['position' => $position, 'salary' => $salary, 'department_id' => $dept, 'date' => $date]);

    employees_apply_due_promotions($pdo);          // applies it right away when the date is today or earlier
    $s = $pdo->prepare("SELECT * FROM promotions WHERE id = ?");
    $s->execute([$pid]);
    json_response(['success' => true, 'data' => ['promotion' => $s->fetch(), 'employee' => employees_fetch($id, $pdo)]], 201);
}

function employees_do_terminate(int $id, ?string $date, ?string $reason, PDO $pdo): void {
    $date = $date ?: att_now($pdo)->format('Y-m-d');
    $pdo->prepare("UPDATE employees SET status = 'inactive', termination_date = ?, termination_reason = ? WHERE id = ? AND company_id = ?")->execute([$date, $reason, $id, cid()]);
    $pdo->prepare("UPDATE users SET status = 'disabled' WHERE employee_id = ? AND company_id = ? AND role = 'employee'")->execute([$id, cid()]);
    $pdo->prepare("DELETE FROM sessions WHERE user_id IN (SELECT id FROM users WHERE employee_id = ? AND company_id = ? AND role = 'employee')")->execute([$id, cid()]);
    // the people they managed move up to the leaver's manager
    $m = $pdo->prepare("SELECT manager_id FROM employees WHERE id = ? AND company_id = ?");
    $m->execute([$id, cid()]);
    $up = $m->fetchColumn();
    $pdo->prepare("UPDATE employees SET manager_id = ? WHERE manager_id = ? AND company_id = ?")->execute([$up ?: null, $id, cid()]);
    $pdo->prepare("UPDATE departments SET head_employee_id = NULL WHERE head_employee_id = ? AND company_id = ?")->execute([$id, cid()]);
    audit($pdo, 'terminate', 'employee', $id, ['date' => $date, 'reason' => $reason]);
}

function employees_terminate(int $id, array $body, PDO $pdo): void {
    if (!in_company($pdo, 'employees', $id)) error_response('Employee not found', 404);
    if ($id === own_employee_id()) error_response('You cannot end your own employment', 422);
    $date = !empty($body['date']) ? (string)$body['date'] : null;
    employees_do_terminate($id, $date, isset($body['reason']) ? mb_substr(trim((string)$body['reason']), 0, 1000) : null, $pdo);
    employees_get_one($id, $pdo);
}

function employees_reinstate(int $id, PDO $pdo): void {
    if (!in_company($pdo, 'employees', $id)) error_response('Employee not found', 404);
    $pdo->prepare("UPDATE employees SET status = 'active', termination_date = NULL, termination_reason = NULL WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
    $pdo->prepare("UPDATE users SET status = 'active' WHERE employee_id = ? AND company_id = ? AND role = 'employee'")->execute([$id, cid()]);
    audit($pdo, 'reinstate', 'employee', $id);
    employees_get_one($id, $pdo);
}
