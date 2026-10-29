<?php
/**
 * Company groups: a holding company with several SEPARATE companies under it.
 *
 * Isolation model (important): every company is its own tenant — all rows carry its company_id and every query is
 * filtered by cid(). The group layer never merges data. A signed-in person always works inside exactly ONE company at a
 * time (sessions.active_company_id, default = the home company of the account); switching changes which single company
 * cid() returns. Whether a switch is allowed is decided here, on the server, on every request:
 *
 *   - super admin (group_admins)           -> may enter every company of the group, with full control
 *   - company_access grant (HR users only) -> may enter that one company, 'full' or 'custom' (chosen modules), optional read-only
 *   - nobody else                          -> never leaves the home company
 *
 * Grants never cross groups, and never apply to plain employee accounts.
 */

/** Every module an HR user can be given in a 'custom' grant (same names as hr_module_for_route()). */
const GROUP_MODULES = ['dashboard', 'employees', 'departments', 'leaves', 'attendance', 'shifts', 'payroll',
                       'recruitment', 'talent_pool', 'reviews', 'announcements', 'documents', 'hr_staff', 'requests'];

/** Routes without a module that a 'custom' grant may still use (everything else, e.g. reports/audit, stays closed). */
const GROUP_CUSTOM_SAFE_ROUTES = ['company', 'notifications', 'profile', 'directory', 'org', 'holidays', 'leave-types', 'group', 'meetings'];

function group_id_of_company(PDO $pdo, int $companyId): ?int {
    $s = $pdo->prepare("SELECT group_id FROM companies WHERE id = ? LIMIT 1");
    $s->execute([$companyId]);
    $g = $s->fetchColumn();
    return $g ? (int)$g : null;
}

/** Is this account the platform owner? (set only by the server-side setup script) */
function group_is_owner(PDO $pdo, int $userId): bool {
    return function_exists('platform_owner_check') && platform_owner_check($pdo, $userId);
}

/** Group the user is super admin of (null when none). */
function group_super_admin_of(PDO $pdo, int $userId): ?int {
    $s = $pdo->prepare("SELECT group_id FROM group_admins WHERE user_id = ? LIMIT 1");
    $s->execute([$userId]);
    $g = $s->fetchColumn();
    return $g ? (int)$g : null;
}

/**
 * What may this account do inside company $companyId? `$user` is the account row with its HOME company_id.
 * Returns null = no access. (The home company itself is handled by the caller.)
 *   ['level' => super|full|custom, 'role' => hr_admin|hr_manager, 'modules' => ?array (null = all), 'read_only' => bool]
 */
function group_resolve_access(PDO $pdo, array $user, int $companyId): ?array {
    $home = (int)$user['company_id'];
    if ($companyId === $home) return null;
    if (!in_array($user['role'] ?? '', ['hr_admin', 'hr_manager'], true)) return null;     // employees never leave their company

    $homeGroup = group_id_of_company($pdo, $home);
    $targetGroup = group_id_of_company($pdo, $companyId);
    if ($homeGroup === null || $targetGroup !== $homeGroup) return null;                    // same group only

    if (group_is_owner($pdo, (int)$user['id'])) {
        return ['level' => 'super', 'role' => 'hr_admin', 'modules' => null, 'read_only' => false];      // the owner enters every company of the group
    }
    if (group_super_admin_of($pdo, (int)$user['id']) === $homeGroup) {
        // A company the owner keeps for himself is opened for the Super Admin only through an explicit grant (below)
        $om = $pdo->prepare("SELECT owner_managed FROM companies WHERE id = ? LIMIT 1");
        $om->execute([$companyId]);
        if (!(int)$om->fetchColumn()) return ['level' => 'super', 'role' => 'hr_admin', 'modules' => null, 'read_only' => false];
    }
    $s = $pdo->prepare("SELECT level, modules, read_only FROM company_access WHERE user_id = ? AND company_id = ? LIMIT 1");
    $s->execute([(int)$user['id'], $companyId]);
    $g = $s->fetch();
    if (!$g) return null;

    $ro = (bool)$g['read_only'];
    if ($g['level'] === 'full') {
        // A read-only person is never a company admin (cannot add users or change settings).
        return ['level' => 'full', 'role' => $ro ? 'hr_manager' : 'hr_admin', 'modules' => null, 'read_only' => $ro];
    }
    $mods = json_decode((string)$g['modules'], true);
    $mods = is_array($mods) ? array_values(array_intersect($mods, GROUP_MODULES)) : [];
    return ['level' => 'custom', 'role' => 'hr_manager', 'modules' => $mods, 'read_only' => $ro];
}

/**
 * Turn the account row (home company) into the row of the company it is currently working in.
 * Falls back to the home company when the stored choice is no longer allowed (grant removed, company suspended...).
 */
function group_apply_context(PDO $pdo, array $user, ?int $active, string $token): array {
    $user['home_company_id'] = (int)$user['company_id'];
    $user['is_away'] = false;
    if (!$active || $active === (int)$user['company_id']) return $user;

    $ctx = group_resolve_access($pdo, $user, $active);
    $c = $pdo->prepare("SELECT status FROM companies WHERE id = ? LIMIT 1");
    $c->execute([$active]);
    $status = $c->fetchColumn();
    if ($ctx === null || $status !== 'active') {
        $pdo->prepare("UPDATE sessions SET active_company_id = NULL WHERE token = ?")->execute([$token]);
        return $user;
    }
    $user['company_id']       = $active;
    $user['company_status']   = $status;
    $user['role']             = $ctx['role'];
    $user['employee_id']      = null;                // the employee record belongs to the home company
    $user['is_away']          = true;
    $user['access_level']     = $ctx['level'];
    $user['access_modules']   = $ctx['modules'];
    $user['access_read_only'] = $ctx['read_only'];
    return $user;
}

/** Companies the account may enter (home first) with the access it has in each. */
function group_companies_for_user(PDO $pdo, array $user, bool $withCounts = false): array {
    $home = (int)($user['home_company_id'] ?? $user['company_id']);
    $gid = group_id_of_company($pdo, $home);
    if ($gid === null) return [];
    $isSuper = group_super_admin_of($pdo, (int)$user['id']) === $gid;
    $isOwner = group_is_owner($pdo, (int)$user['id']);

    $rows = $pdo->prepare(
        "SELECT c.id, c.name, c.slug, c.logo_url, c.primary_color, c.accent_color, c.status, c.ceo_user_id, c.owner_managed,
                u.name AS ceo_name, u.email AS ceo_email,
                a.level AS grant_level, a.modules AS grant_modules, a.read_only AS grant_read_only
         FROM companies c
         LEFT JOIN users u ON u.id = c.ceo_user_id
         LEFT JOIN company_access a ON a.company_id = c.id AND a.user_id = ?
         WHERE c.group_id = ?
         ORDER BY (c.id = ?) DESC, c.name"
    );
    $rows->execute([(int)$user['id'], $gid, $home]);

    $out = [];
    foreach ($rows->fetchAll() as $r) {
        $isHome = (int)$r['id'] === $home;
        $om = (bool)(int)($r['owner_managed'] ?? 0);
        $full = $isOwner || ($isSuper && !$om);          // the owner sees everything; a Super Admin sees what the owner did not keep for himself
        if (!$isHome && !$full && $r['grant_level'] === null) continue;
        if (!$isHome && !in_array($user['role'] ?? ($user['home_role'] ?? ''), ['hr_admin', 'hr_manager'], true)) continue;
        $access = $isHome ? ['level' => 'home', 'read_only' => false, 'modules' => null]
            : ($full ? ['level' => 'super', 'read_only' => false, 'modules' => null]
                : ['level' => $r['grant_level'], 'read_only' => (bool)$r['grant_read_only'],
                   'modules' => $r['grant_level'] === 'custom' ? (json_decode((string)$r['grant_modules'], true) ?: []) : null]);
        $row = [
            'id' => (int)$r['id'], 'name' => $r['name'], 'slug' => $r['slug'], 'logo_url' => $r['logo_url'],
            'primary_color' => $r['primary_color'], 'accent_color' => $r['accent_color'], 'status' => $r['status'],
            'is_home' => $isHome,
            'owner_managed' => $om,
            'ceo' => $r['ceo_user_id'] ? ['id' => (int)$r['ceo_user_id'], 'name' => $r['ceo_name'], 'email' => $r['ceo_email']] : null,
            'access' => $access,
        ];
        if ($withCounts) {
            // who runs this company: its own HR accounts plus the HR people who were given access from other companies
            $m = $pdo->prepare(
                "SELECT u.id, u.name, u.email, 'own' AS source FROM users u WHERE u.company_id = ? AND u.role IN ('hr_admin','hr_manager') AND u.status = 'active'
                 UNION
                 SELECT u.id, u.name, u.email, 'granted' AS source FROM company_access a JOIN users u ON u.id = a.user_id WHERE a.company_id = ? AND u.status = 'active'
                 ORDER BY name"
            );
            $m->execute([(int)$r['id'], (int)$r['id']]);
            $row['managers'] = $m->fetchAll();
            $e = $pdo->prepare("SELECT COUNT(*) FROM employees WHERE company_id = ? AND status != 'inactive'");
            $e->execute([(int)$r['id']]);
            $d = $pdo->prepare("SELECT COUNT(*) FROM departments WHERE company_id = ?");
            $d->execute([(int)$r['id']]);
            $row['employee_count'] = (int)$e->fetchColumn();
            $row['department_count'] = (int)$d->fetchColumn();
        }
        $out[] = $row;
    }
    return $out;
}

/** Group block sent with the sign-in / me responses so the apps can show a company switcher. null = not part of a group. */
function group_context_payload(PDO $pdo, array $user): ?array {
    $home = (int)($user['home_company_id'] ?? $user['company_id']);
    $gid = group_id_of_company($pdo, $home);
    if ($gid === null) return null;
    $g = $pdo->prepare("SELECT id, name, slug FROM company_groups WHERE id = ? LIMIT 1");
    $g->execute([$gid]);
    $group = $g->fetch();
    if (!$group) return null;
    $user['home_company_id'] = $home;
    $companies = group_companies_for_user($pdo, $user);
    return [
        'id' => (int)$group['id'], 'name' => $group['name'], 'slug' => $group['slug'],
        'is_super_admin' => group_super_admin_of($pdo, (int)$user['id']) === $gid,
        'is_owner' => group_is_owner($pdo, (int)$user['id']),
        'home_company_id' => $home,
        'active_company_id' => (int)$user['company_id'],
        'companies' => $companies,
    ];
}

/** Starter data every new company gets (leave types, documents, a day shift, leave policy). */
function company_seed_defaults(PDO $pdo, int $companyId): void {
    $lt = $pdo->prepare("INSERT INTO leave_types (company_id, code, name, days_per_year, paid, color) VALUES (?,?,?,?,?,?)");
    foreach ([['annual', 'Annual leave', 21, 1, '#4F46E5'], ['sick', 'Sick leave', 10, 1, '#EF4444'],
              ['casual', 'Casual leave', 6, 1, '#F59E0B'], ['unpaid', 'Unpaid leave', 0, 0, '#64748B']] as $t) {
        $lt->execute(array_merge([$companyId], $t));
    }
    $dt = $pdo->prepare("INSERT INTO required_document_types (company_id, label, order_num) VALUES (?, ?, ?)");
    foreach (['National ID', 'Resume / CV', 'Employment contract', 'Bank details'] as $n => $label) {
        $dt->execute([$companyId, $label, $n + 1]);
    }
    $pdo->prepare("INSERT INTO shifts (company_id, name, start_time, end_time, color, days) VALUES (?, 'Day shift', '09:00:00', '17:00:00', '#4F46E5', 'sun,mon,tue,wed,thu')")->execute([$companyId]);
    $pdo->prepare("INSERT INTO leave_policy (company_id, days_per_month, days_per_year) VALUES (?, 2, 21)")->execute([$companyId]);
}

// ------------------------------------------------------------------------------------------------ shared people / departments
// A company can share one of its employees or departments with other companies of the same group (table group_shares).
// The owner of the item stays the only one who can change it; the other company sees it and (for a department) can put its own
// people in it. Everything else about a company stays isolated.

/** Is department $id one of this company's own, or shared into it? */
function department_visible(PDO $pdo, ?int $id): bool {
    if (!$id) return false;
    $s = $pdo->prepare("SELECT 1 FROM departments d WHERE d.id = ? AND (d.company_id = ? OR EXISTS
        (SELECT 1 FROM group_shares g WHERE g.kind = 'department' AND g.item_id = d.id AND g.target_company_id = ?)) LIMIT 1");
    $s->execute([$id, cid(), cid()]);
    return (bool)$s->fetchColumn();
}

/** Companies this person may share things with: the group's other active companies (a company the owner keeps for himself only for the owner). */
function group_share_targets(PDO $pdo): array {
    $gid = group_id_of_company($pdo, cid());
    if ($gid === null) return [];
    $owner = group_is_owner($pdo, (int)me()['id']);
    $s = $pdo->prepare("SELECT id, name FROM companies WHERE group_id = ? AND status = 'active' AND id != ?" . ($owner ? '' : ' AND owner_managed = 0') . " ORDER BY name");
    $s->execute([$gid, cid()]);
    return $s->fetchAll();
}

/** item id => how many other companies it is shared with, for this company's items of $kind. */
function group_share_counts(PDO $pdo, string $kind): array {
    $s = $pdo->prepare("SELECT item_id, COUNT(*) FROM group_shares WHERE kind = ? AND source_company_id = ? GROUP BY item_id");
    $s->execute([$kind, cid()]);
    return $s->fetchAll(PDO::FETCH_KEY_PAIR);
}
