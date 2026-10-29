<?php
/**
 * Company group API (see helpers/group.php for the isolation model).
 *
 *   GET    /group                          the group, the companies the caller may enter, which one is active   (any HR user of the group)
 *   POST   /group/switch                   {company_id}  work inside another allowed company (null/home = back home)
 *   GET    /group/companies                same list with employee / department counts                          (super admin)
 *   POST   /group/companies                {name, ceo_name, ceo_email, ceo_password, ...}  new company + its CEO   (super admin)
 *   PUT    /group/companies/:id            {name?, status?, timezone?, currency?}                               (super admin)
 *   POST   /group/companies/:id/ceo        {name, email, password}  new CEO account for the company            (super admin)
 *   GET    /group/people                   HR accounts of the whole group (to pick who gets access)            (super admin)
 *   GET    /group/access                   every extra-access grant                                              (super admin)
 *   GET    /group/hr-accounts              every HR admin / HR manager account of the group, any status          (owner only)
 *   PUT    /group/hr-accounts/:id          {status: active|disabled}  close or reopen an HR account            (owner only)
 *   POST   /group/access                   {user_id, company_id, level: full|custom, modules?, read_only?}       (super admin)
 *   DELETE /group/access/:id               take the access away again                                           (super admin)
 *   GET    /group/shares?kind=employee|department&id=N     which companies this person / department is shared with (HR of the owning company)
 *   GET    /group/transfer-targets?kind=   companies the caller may move an employee / department into        (HR with full access to both)
 *   GET    /group/transfer-departments?company_id=N   departments of such a company
 *   POST   /group/transfer         {kind, id, target_company_id, department_id?, move_members?}  move it to that company
 *   PUT    /group/shares                   {kind, id, company_ids: []}  share it with exactly these companies   (HR of the owning company)
 */
require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/../helpers/transfer.php';

function handle_group(string $path, string $method, array $body): void {
    $pdo = getDB();
    $seg = explode('/', $path);
    $sub = $seg[1] ?? '';
    $id  = isset($seg[2]) && ctype_digit($seg[2]) ? (int)$seg[2] : null;
    $action = $seg[3] ?? '';

    $homeId = (int)(me()['home_company_id'] ?? me()['company_id']);
    $gid = group_id_of_company($pdo, $homeId);
    if ($gid === null) error_response('Company groups are not enabled for this account.', 404);

    switch ($sub) {
        case '':
            if ($method !== 'GET') error_response('Method not allowed', 405);
            group_overview($pdo, $gid, false);
            break;
        case 'switch':
            if ($method !== 'POST') error_response('Method not allowed', 405);
            group_switch($body, $pdo);
            break;
        case 'search':      // owner only: employee search over every company of the group (the top-bar search box)
            if ($method !== 'GET') error_response('Method not allowed', 405);
            require_once __DIR__ . '/employees.php';
            employees_search_all_companies($pdo, $gid);
            break;
        case 'companies':
            group_require_super($pdo, $gid);
            if ($id === null) {
                if ($method === 'GET')  group_overview($pdo, $gid, true);
                if ($method === 'POST') group_company_create($body, $pdo, $gid);
            } elseif ($action === '' && $method === 'PUT') {
                group_company_update($id, $body, $pdo, $gid);
            } elseif ($action === 'ceo' && $method === 'POST') {
                group_company_new_ceo($id, $body, $pdo, $gid);
            }
            error_response('Method not allowed', 405);
            break;
        case 'people':
            group_require_super($pdo, $gid);
            if ($method !== 'GET') error_response('Method not allowed', 405);
            group_people($pdo, $gid);
            break;
        case 'hr-accounts':          // the owner's view of every HR manager of the group, and the switch that closes one
            if (!group_is_owner($pdo, (int)me()['id'])) error_response('Only the owner can do this.', 403);
            if ($method === 'GET' && $id === null) group_hr_accounts($pdo, $gid);
            if ($method === 'PUT' && $id !== null) group_hr_account_set($id, $body, $pdo, $gid);
            error_response('Method not allowed', 405);
            break;
        case 'access':
            group_require_super($pdo, $gid);
            if ($method === 'GET' && $id === null) group_access_list($pdo, $gid);
            if ($method === 'POST' && $id === null) group_access_set($body, $pdo, $gid);
            if ($method === 'DELETE' && $id !== null) group_access_remove($id, $pdo, $gid);
            error_response('Method not allowed', 405);
            break;
        case 'transfer-targets':
            require_hr();
            if ($method !== 'GET') error_response('Method not allowed', 405);
            json_response(['success' => true, 'data' => transfer_targets($pdo, ($_GET['kind'] ?? '') === 'department' ? 'departments' : 'employees')]);
            break;
        case 'transfer-departments':
            require_hr();
            if ($method !== 'GET') error_response('Method not allowed', 405);
            json_response(['success' => true, 'data' => transfer_target_departments($pdo, (int)($_GET['company_id'] ?? 0))]);
            break;
        case 'transfer':
            require_hr();
            if ($method !== 'POST') error_response('Method not allowed', 405);
            transfer_run($body, $pdo);
            break;
        case 'shares':
            require_hr();
            if ($method === 'GET') group_shares_get($pdo);
            if ($method === 'PUT' || $method === 'POST') group_shares_set($body, $pdo, $gid);
            error_response('Method not allowed', 405);
            break;
        default:
            error_response('Not found', 404);
    }
}

/** The item (own employee / department) a share request is about, or a 404/422. Returns [kind, id]. */
function group_share_item(PDO $pdo, $kind, $id): array {
    $kind = (string)$kind;
    $id = int_or_null($id);
    if (!in_array($kind, ['employee', 'department'], true)) error_response('kind must be employee or department', 422);
    if (!in_company($pdo, $kind === 'employee' ? 'employees' : 'departments', $id)) error_response('Not found in this company', 404);
    return [$kind, (int)$id];
}

function group_shares_get(PDO $pdo): void {
    [$kind, $id] = group_share_item($pdo, $_GET['kind'] ?? '', $_GET['id'] ?? null);
    $on = $pdo->prepare("SELECT target_company_id FROM group_shares WHERE kind = ? AND item_id = ?");
    $on->execute([$kind, $id]);
    $shared = array_map('intval', $on->fetchAll(PDO::FETCH_COLUMN));
    $out = array_map(fn($c) => ['id' => (int)$c['id'], 'name' => $c['name'], 'shared' => in_array((int)$c['id'], $shared, true)], group_share_targets($pdo));
    json_response(['success' => true, 'data' => ['kind' => $kind, 'item_id' => $id, 'companies' => $out]]);
}

function group_shares_set(array $body, PDO $pdo, int $gid): void {
    if (!empty(me()['access_read_only'])) error_response('You have read-only access to this company.', 403);
    [$kind, $id] = group_share_item($pdo, $body['kind'] ?? '', $body['id'] ?? null);
    $allowed = array_map(fn($c) => (int)$c['id'], group_share_targets($pdo));
    $want = array_values(array_unique(array_map('intval', (array)($body['company_ids'] ?? []))));
    foreach ($want as $w) if (!in_array($w, $allowed, true)) error_response('You can only share with the other companies of the group.', 422);

    $cur = $pdo->prepare("SELECT target_company_id FROM group_shares WHERE kind = ? AND item_id = ?");
    $cur->execute([$kind, $id]);
    $have = array_map('intval', $cur->fetchAll(PDO::FETCH_COLUMN));
    foreach (array_diff($have, $want) as $gone) {
        $pdo->prepare("DELETE FROM group_shares WHERE kind = ? AND item_id = ? AND target_company_id = ?")->execute([$kind, $id, $gone]);
        // a department taken away from a company: that company's people are no longer in it
        if ($kind === 'department') $pdo->prepare("UPDATE employees SET department_id = NULL WHERE department_id = ? AND company_id = ?")->execute([$id, $gone]);
    }
    foreach (array_diff($want, $have) as $new) {
        $pdo->prepare("INSERT INTO group_shares (group_id, kind, item_id, source_company_id, target_company_id, created_by) VALUES (?,?,?,?,?,?)")
            ->execute([$gid, $kind, $id, cid(), $new, (int)me()['id']]);
    }
    audit($pdo, 'share', $kind, $id, ['company_ids' => $want]);
    $_GET['kind'] = $kind;
    $_GET['id'] = $id;
    group_shares_get($pdo);
}

/** The platform owner or the super admin of the caller's group passes. Uses the real account, never the company currently entered. */
function group_require_super(PDO $pdo, int $gid): void {
    if (group_is_owner($pdo, (int)me()['id'])) return;
    if (group_super_admin_of($pdo, (int)me()['id']) !== $gid) {
        error_response('Only the owner or the group super admin can do this.', 403);
    }
}

function group_overview(PDO $pdo, int $gid, bool $withCounts): void {
    $g = $pdo->prepare("SELECT id, name, slug FROM company_groups WHERE id = ?");
    $g->execute([$gid]);
    $u = me();
    json_response([
        'success' => true,
        'data' => [
            'group' => $g->fetch(),
            'is_super_admin' => group_super_admin_of($pdo, (int)$u['id']) === $gid,
            'is_owner' => group_is_owner($pdo, (int)$u['id']),
            'home_company_id' => (int)$u['home_company_id'],
            'active_company_id' => (int)$u['company_id'],
            'companies' => group_companies_for_user($pdo, $u, $withCounts),
        ],
    ]);
}

function group_switch(array $body, PDO $pdo): void {
    $u = me();
    $target = (int)($body['company_id'] ?? 0);
    $home = (int)$u['home_company_id'];
    if ($target <= 0) $target = $home;

    if ($target !== $home) {
        $ctx = group_resolve_access($pdo, array_merge($u, ['company_id' => $home]), $target);
        if ($ctx === null) error_response('You do not have access to this company.', 403);
        $c = $pdo->prepare("SELECT status FROM companies WHERE id = ?");
        $c->execute([$target]);
        if ($c->fetchColumn() !== 'active') error_response('This company is suspended.', 403);
    }
    $pdo->prepare("UPDATE sessions SET active_company_id = ? WHERE token = ?")
        ->execute([$target === $home ? null : $target, get_bearer_token()]);

    // Answer with the new working context, exactly like /auth/me
    $fresh = get_authenticated_user();
    if (!$fresh) error_response('Unauthorized. Please log in.', 401);
    hr_set_user($fresh);
    audit($pdo, 'switch_company', 'company', $target);
    auth_me($pdo);
}

// ------------------------------------------------------------------ companies

function group_company_in_group(PDO $pdo, int $companyId, int $gid): array {
    $c = $pdo->prepare("SELECT * FROM companies WHERE id = ? AND group_id = ? LIMIT 1");
    $c->execute([$companyId, $gid]);
    $row = $c->fetch();
    if (!$row) error_response('Company not found in this group.', 404);
    // A company the owner keeps for himself does not exist for a Super Admin who was not given access to it
    if ((int)($row['owner_managed'] ?? 0) && !group_is_owner($pdo, (int)me()['id'])) {
        $a = $pdo->prepare("SELECT 1 FROM company_access WHERE user_id = ? AND company_id = ? LIMIT 1");
        $a->execute([(int)me()['id'], $companyId]);
        if (!$a->fetchColumn()) error_response('Company not found in this group.', 404);
    }
    return $row;
}

function group_email_taken(PDO $pdo, string $email): bool {
    $s = $pdo->prepare("SELECT 1 FROM users WHERE email = ? UNION SELECT 1 FROM employees WHERE email = ? LIMIT 1");
    $s->execute([$email, $email]);
    return (bool)$s->fetchColumn();
}

/** Validate and normalise the CEO fields of a request. */
function group_ceo_input(array $in, string $prefix, PDO $pdo): array {
    $name = trim((string)($in[$prefix . 'name'] ?? ''));
    $email = strtolower(trim((string)($in[$prefix . 'email'] ?? '')));
    $password = (string)($in[$prefix . 'password'] ?? '');
    if ($name === '' || $email === '' || $password === '') error_response('The CEO name, e-mail and password are required.', 422);
    if (mb_strlen($name) > 120) error_response('Name is too long', 422);
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) error_response('Invalid CEO e-mail address', 422);
    auth_check_password_strength($password);
    if (group_email_taken($pdo, $email)) error_response('An account with this e-mail already exists', 409);
    return [$name, $email, $password];
}

function group_company_create(array $body, PDO $pdo, int $gid): void {
    // Only the owner opens new companies. A Super Admin / HR manager never does.
    if (!group_is_owner($pdo, (int)me()['id'])) error_response('Only the owner can create a company.', 403);
    $name = trim((string)($body['name'] ?? ''));
    if ($name === '' || mb_strlen($name) > 120) error_response('Company name is required (up to 120 characters).', 422);
    // Who runs it: HR managers the owner picks from the group (they get full access) and/or a brand-new HR account. Both are optional.
    $wantsNew = trim((string)($body['ceo_name'] ?? '')) !== '' || trim((string)($body['ceo_email'] ?? '')) !== '' || (string)($body['ceo_password'] ?? '') !== '';
    $ceo = $wantsNew ? group_ceo_input($body, 'ceo_', $pdo) : null;
    $pickIds = array_values(array_unique(array_filter(array_map('intval', is_array($body['hr_user_ids'] ?? null) ? $body['hr_user_ids'] : []))));
    $picked = [];
    if ($pickIds) {
        $q = $pdo->prepare("SELECT u.id FROM users u JOIN companies c ON c.id = u.company_id WHERE c.group_id = ? AND u.status = 'active' AND u.role IN ('hr_admin','hr_manager') AND u.id IN (" . implode(',', $pickIds) . ")");
        $q->execute([$gid]);
        $picked = array_map('intval', $q->fetchAll(PDO::FETCH_COLUMN));
        if (count($picked) !== count($pickIds)) error_response('One of the chosen HR managers was not found in this group.', 404);
    }

    $tz = $body['timezone'] ?? 'Africa/Cairo';
    if (!in_array($tz, timezone_identifiers_list(), true)) $tz = 'Africa/Cairo';
    $currency = strtoupper(substr(preg_replace('/[^A-Za-z]/', '', (string)($body['currency'] ?? 'EGP')), 0, 3)) ?: 'EGP';

    $slug = auth_slugify($name); $base = $slug; $i = 1;
    $chk = $pdo->prepare("SELECT 1 FROM companies WHERE slug = ?");
    while (true) { $chk->execute([$slug]); if (!$chk->fetchColumn()) break; $slug = $base . '-' . (++$i); }

    $pdo->beginTransaction();
    try {
        $pdo->prepare("INSERT INTO companies (name, slug, timezone, currency, group_id, owner_managed) VALUES (?, ?, ?, ?, ?, 1)")->execute([$name, $slug, $tz, $currency, $gid]);
        $companyId = (int)$pdo->lastInsertId();
        $ceoId = null;
        if ($ceo) {
            [$ceoName, $ceoEmail, $ceoPassword] = $ceo;
            $pdo->prepare("INSERT INTO users (company_id, name, email, password_hash, role, title, phone, status, created_by, created_at) VALUES (?, ?, ?, ?, 'hr_admin', 'CEO', ?, 'active', ?, NOW())")
                ->execute([$companyId, $ceoName, $ceoEmail, password_hash($ceoPassword, PASSWORD_BCRYPT), $body['ceo_phone'] ?? null, (int)me()['id']]);
            $ceoId = (int)$pdo->lastInsertId();
            $pdo->prepare("UPDATE companies SET ceo_user_id = ? WHERE id = ?")->execute([$ceoId, $companyId]);
        }
        foreach ($picked as $uid) {
            $pdo->prepare("INSERT INTO company_access (user_id, company_id, level, modules, read_only, granted_by) VALUES (?, ?, 'full', NULL, 0, ?)")->execute([$uid, $companyId, (int)me()['id']]);
        }
        company_seed_defaults($pdo, $companyId);
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        error_log('[HR API] group company create failed: ' . $e->getMessage());
        error_response('Could not create the company. Please try again.', 500);
    }
    audit($pdo, 'create_company', 'company', $companyId, ['name' => $name, 'new_hr' => $ceo ? $ceo[1] : null, 'hr_user_ids' => $picked]);
    json_response(['success' => true, 'data' => ['id' => $companyId, 'name' => $name, 'slug' => $slug, 'owner_managed' => true, 'granted' => $picked,
        'ceo' => $ceo ? ['id' => $ceoId, 'name' => $ceo[0], 'email' => $ceo[1]] : null]], 201);
}

function group_company_update(int $id, array $body, PDO $pdo, int $gid): void {
    $c = group_company_in_group($pdo, $id, $gid);
    $sets = []; $vals = [];
    if (isset($body['name'])) {
        $n = trim((string)$body['name']);
        if ($n === '' || mb_strlen($n) > 120) error_response('Company name is required (up to 120 characters).', 422);
        $sets[] = 'name = ?'; $vals[] = $n;
    }
    if (array_key_exists('owner_managed', $body)) {
        if (!group_is_owner($pdo, (int)me()['id'])) error_response('Only the owner can change who sees a company.', 403);
        $sets[] = 'owner_managed = ?'; $vals[] = empty($body['owner_managed']) ? 0 : 1;
    }
    if (isset($body['status'])) {
        if (!in_array($body['status'], ['active', 'suspended'], true)) error_response('Invalid status', 422);
        if ($body['status'] === 'suspended' && $id === (int)me()['home_company_id']) error_response('The company you belong to cannot be suspended.', 422);
        $sets[] = 'status = ?'; $vals[] = $body['status'];
    }
    if (isset($body['timezone'])) {
        if (!in_array($body['timezone'], timezone_identifiers_list(), true)) error_response('Invalid timezone', 422);
        $sets[] = 'timezone = ?'; $vals[] = $body['timezone'];
    }
    if (isset($body['currency'])) {
        $cur = strtoupper(substr(preg_replace('/[^A-Za-z]/', '', (string)$body['currency']), 0, 3));
        if ($cur === '') error_response('Invalid currency', 422);
        $sets[] = 'currency = ?'; $vals[] = $cur;
    }
    if (!$sets) error_response('No fields to update');
    $vals[] = $id;
    $pdo->prepare("UPDATE companies SET " . implode(', ', $sets) . " WHERE id = ?")->execute($vals);
    if (($body['status'] ?? '') === 'suspended') $pdo->prepare("DELETE FROM sessions WHERE active_company_id = ?")->execute([$id]);
    audit($pdo, 'update_company', 'company', $id, array_intersect_key($body, array_flip(['name', 'status', 'timezone', 'currency', 'owner_managed'])));
    json_response(['success' => true, 'data' => ['id' => $id]]);
}

function group_company_new_ceo(int $id, array $body, PDO $pdo, int $gid): void {
    group_company_in_group($pdo, $id, $gid);
    [$name, $email, $password] = group_ceo_input($body, '', $pdo);
    $pdo->prepare("INSERT INTO users (company_id, name, email, password_hash, role, title, phone, status, created_by, created_at) VALUES (?, ?, ?, ?, 'hr_admin', 'CEO', ?, 'active', ?, NOW())")
        ->execute([$id, $name, $email, password_hash($password, PASSWORD_BCRYPT), $body['phone'] ?? null, (int)me()['id']]);
    $ceoId = (int)$pdo->lastInsertId();
    $pdo->prepare("UPDATE companies SET ceo_user_id = ? WHERE id = ?")->execute([$ceoId, $id]);
    audit($pdo, 'set_ceo', 'company', $id, ['ceo' => $email]);
    json_response(['success' => true, 'data' => ['id' => $ceoId, 'name' => $name, 'email' => $email]], 201);
}

// ----------------------------------------------------------- people and access

function group_people(PDO $pdo, int $gid): void {
    $s = $pdo->prepare(
        "SELECT u.id, u.name, u.email, u.role, u.title, u.company_id, c.name AS company_name,
                (SELECT COUNT(*) FROM group_admins ga WHERE ga.user_id = u.id AND ga.group_id = c.group_id) AS is_super_admin
         FROM users u JOIN companies c ON c.id = u.company_id
         WHERE c.group_id = ? AND u.role IN ('hr_admin','hr_manager') AND u.status = 'active'
         ORDER BY c.name, u.name"
    );
    $s->execute([$gid]);
    json_response(['success' => true, 'data' => $s->fetchAll()]);
}

/** Owner: every HR admin / HR manager of the group (active or closed), where they work and how far their access reaches. */
function group_hr_accounts(PDO $pdo, int $gid): void {
    $s = $pdo->prepare(
        "SELECT u.id, u.name, u.email, u.role, u.title, u.phone, u.status, u.last_login_at, u.created_at,
                u.company_id, c.name AS company_name,
                (SELECT COUNT(*) FROM group_admins ga WHERE ga.user_id = u.id AND ga.group_id = c.group_id) AS is_super_admin,
                (SELECT COUNT(*) FROM platform_owners po WHERE po.user_id = u.id) AS is_owner,
                (SELECT COUNT(*) FROM company_access a WHERE a.user_id = u.id) AS extra_companies
         FROM users u JOIN companies c ON c.id = u.company_id
         WHERE c.group_id = ? AND u.role IN ('hr_admin','hr_manager')
         ORDER BY is_owner DESC, is_super_admin DESC, c.name, u.name"
    );
    $s->execute([$gid]);
    $rows = $s->fetchAll();
    foreach ($rows as &$r) { $r['is_super_admin'] = (int)$r['is_super_admin'] > 0; $r['is_owner'] = (int)$r['is_owner'] > 0; $r['extra_companies'] = (int)$r['extra_companies']; }
    json_response(['success' => true, 'data' => $rows]);
}

/** Owner: close ({status: disabled}) or reopen ({status: active}) one HR account. A closed account is signed out at once and cannot sign in. */
function group_hr_account_set(int $id, array $body, PDO $pdo, int $gid): void {
    $status = (string)($body['status'] ?? '');
    if (!in_array($status, ['active', 'disabled'], true)) error_response("status must be 'active' or 'disabled'", 422);
    if ($id === (int)me()['id']) error_response('You cannot close your own account.', 422);
    if (group_is_owner($pdo, $id)) error_response('The owner account cannot be closed here.', 422);
    $u = $pdo->prepare("SELECT u.id, u.name, u.company_id FROM users u JOIN companies c ON c.id = u.company_id WHERE u.id = ? AND c.group_id = ? AND u.role IN ('hr_admin','hr_manager')");
    $u->execute([$id, $gid]);
    $user = $u->fetch();
    if (!$user) error_response('HR account not found in this group.', 404);
    $pdo->prepare("UPDATE users SET status = ? WHERE id = ?")->execute([$status, $id]);
    if ($status !== 'active') $pdo->prepare("DELETE FROM sessions WHERE user_id = ?")->execute([$id]);
    audit($pdo, $status === 'active' ? 'reopen_hr_account' : 'close_hr_account', 'user', $id, ['name' => $user['name']]);
    json_response(['success' => true, 'data' => ['id' => $id, 'status' => $status]]);
}

function group_access_list(PDO $pdo, int $gid): void {
    $s = $pdo->prepare(
        "SELECT a.id, a.user_id, a.company_id, a.level, a.modules, a.read_only, a.created_at,
                u.name AS user_name, u.email AS user_email, hc.name AS home_company_name, tc.name AS company_name
         FROM company_access a
         JOIN users u ON u.id = a.user_id
         JOIN companies hc ON hc.id = u.company_id
         JOIN companies tc ON tc.id = a.company_id
         WHERE tc.group_id = ? AND (tc.owner_managed = 0 OR ? = 1 OR EXISTS (SELECT 1 FROM company_access mine WHERE mine.company_id = tc.id AND mine.user_id = ?))
         ORDER BY u.name, tc.name"
    );
    $s->execute([$gid, group_is_owner($pdo, (int)me()['id']) ? 1 : 0, (int)me()['id']]);
    $rows = $s->fetchAll();
    foreach ($rows as &$r) {
        $r['modules'] = $r['level'] === 'custom' ? (json_decode((string)$r['modules'], true) ?: []) : null;
        $r['read_only'] = (bool)$r['read_only'];
    }
    json_response(['success' => true, 'data' => $rows]);
}

function group_access_set(array $body, PDO $pdo, int $gid): void {
    $userId = (int)($body['user_id'] ?? 0);
    $companyId = (int)($body['company_id'] ?? 0);
    $level = (string)($body['level'] ?? 'full');
    if ($userId <= 0 || $companyId <= 0) error_response('user_id and company_id are required', 422);
    if (!in_array($level, ['full', 'custom'], true)) error_response("level must be 'full' or 'custom'", 422);

    $u = $pdo->prepare("SELECT u.id, u.role, u.company_id FROM users u JOIN companies c ON c.id = u.company_id WHERE u.id = ? AND c.group_id = ? AND u.status = 'active'");
    $u->execute([$userId, $gid]);
    $user = $u->fetch();
    if (!$user) error_response('Person not found in this group.', 404);
    if (!in_array($user['role'], ['hr_admin', 'hr_manager'], true)) error_response('Only HR accounts can be given access to another company.', 422);
    $cRow = group_company_in_group($pdo, $companyId, $gid);
    if ((int)$user['company_id'] === $companyId) error_response('This is already the person\'s own company.', 422);
    if (group_is_owner($pdo, $userId)) error_response('The owner already has access to every company.', 422);
    if (group_super_admin_of($pdo, $userId) === $gid && !(int)($cRow['owner_managed'] ?? 0)) error_response('A super admin already has access to every company.', 422);

    $modules = null;
    if ($level === 'custom') {
        $given = is_array($body['modules'] ?? null) ? $body['modules'] : [];
        $modules = array_values(array_unique(array_intersect(array_map('strval', $given), GROUP_MODULES)));
        if (!$modules) error_response('Choose at least one module for a custom access.', 422);
    }
    $pdo->prepare(
        "INSERT INTO company_access (user_id, company_id, level, modules, read_only, granted_by) VALUES (?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE level = VALUES(level), modules = VALUES(modules), read_only = VALUES(read_only), granted_by = VALUES(granted_by)"
    )->execute([$userId, $companyId, $level, $modules === null ? null : json_encode($modules), empty($body['read_only']) ? 0 : 1, (int)me()['id']]);
    audit($pdo, 'grant_access', 'company', $companyId, ['user_id' => $userId, 'level' => $level, 'modules' => $modules, 'read_only' => !empty($body['read_only'])]);
    json_response(['success' => true, 'data' => ['user_id' => $userId, 'company_id' => $companyId, 'level' => $level]], 201);
}

function group_access_remove(int $id, PDO $pdo, int $gid): void {
    $s = $pdo->prepare("SELECT a.user_id, a.company_id FROM company_access a JOIN companies c ON c.id = a.company_id WHERE a.id = ? AND c.group_id = ?");
    $s->execute([$id, $gid]);
    $a = $s->fetch();
    if (!$a) error_response('Access not found.', 404);
    $pdo->prepare("DELETE FROM company_access WHERE id = ?")->execute([$id]);
    // Whoever is working in that company right now is sent back home on their next request
    $pdo->prepare("UPDATE sessions SET active_company_id = NULL WHERE user_id = ? AND active_company_id = ?")->execute([(int)$a['user_id'], (int)$a['company_id']]);
    audit($pdo, 'revoke_access', 'company', (int)$a['company_id'], ['user_id' => (int)$a['user_id']]);
    json_response(['success' => true, 'data' => ['removed' => true]]);
}
