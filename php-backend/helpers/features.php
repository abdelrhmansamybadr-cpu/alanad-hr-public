<?php
/**
 * Owner-controlled premium features.
 *
 * Every feature below is OFF for a company until the platform owner (or, where company groups exist, the group's Super
 * Admin) switches it on for that company. The switch is enforced on the SERVER:
 *   - index.php refuses every request to a feature's routes with 403 {error, code: 'feature_disabled'} (feature_gate()),
 *   - code that lives inside other modules (payroll, attendance...) asks feature_enabled() before it adds the feature's behaviour,
 *   - the apps get the on/off map in the company settings (company_public()['features']) and hide the screens,
 *     but hiding is only a courtesy: switching a feature off closes it even for an old app that still shows it.
 * Switching a feature off never deletes data; switching it on again brings it back as it was.
 */

/** The catalogue. `routes` = API root segments that belong to the feature (all of them are closed when it is off). */
function feature_registry(): array {
    return [
        'approval_chain' => [
            'title_en' => 'Two-step approvals (head, then HR)', 'title_ar' => 'الموافقة على مرحلتين (رئيس الفريق ثم الموارد البشرية)',
            'desc_en' => 'Leave and other requests go to the team head first. Only after the head approves does HR decide.',
            'desc_ar' => 'الإجازات والطلبات تذهب أولاً لرئيس الفريق، وبعد موافقته فقط تقرر الموارد البشرية.',
            'routes' => [],
        ],
        'complaints' => [
            'title_en' => 'Complaints (head, HR, owner)', 'title_ar' => 'الشكاوى (رئيس الفريق، الموارد البشرية، المالك)',
            'desc_en' => 'Team heads file complaints about a team member or to HR. HR resolves them or sends them to the owner.',
            'desc_ar' => 'رؤساء الفرق يقدمون شكوى عن أحد فريقهم أو إلى الموارد البشرية، والموارد تحلها أو ترفعها للمالك.',
            'routes' => ['complaints'],
        ],
        'local_laws' => [
            'title_en' => 'Local labour law & insurance', 'title_ar' => 'قوانين العمل والتأمينات المحلية',
            'desc_en' => 'Egyptian and Saudi labour-law rules, social insurance, tax brackets and Hijri dates calculated automatically.',
            'desc_ar' => 'قانون العمل المصري والسعودي والتأمينات وشرائح الضرائب والتاريخ الهجري تُحسب تلقائياً.',
            'routes' => ['labor-law'],
        ],
        'arabic_pack' => [
            'title_en' => 'Real Arabic pack', 'title_ar' => 'الحزمة العربية الكاملة',
            'desc_en' => 'Documents (payslip, contract, letters) in proper Arabic and Arabic voice commands.',
            'desc_ar' => 'مستندات (قسيمة مرتب، عقد، خطابات) بعربي سليم وأوامر صوتية بالعربي.',
            'routes' => ['arabic'],
        ],
        'fair_decisions' => [
            'title_en' => 'Fair decisions (reason + dispute)', 'title_ar' => 'القرارات العادلة (السبب والاعتراض)',
            'desc_en' => 'Every decision shows its reason; employees can dispute it and the manager answers on the record.',
            'desc_ar' => 'كل قرار يظهر سببه، والموظف يعترض عليه والمدير يرد ويُسجَّل كل شيء.',
            'routes' => ['decisions'],
        ],
        'group_dashboard' => [
            'title_en' => 'Owner dashboard (all companies)', 'title_ar' => 'لوحة صاحب الشركات',
            'desc_en' => 'One picture of every company: cost, lateness, turnover risk and overloaded managers.',
            'desc_ar' => 'صورة واحدة لكل الشركات: التكلفة والتأخير وخطر ترك العمل والمديرين المضغوطين.',
            'routes' => ['portfolio'],
        ],
        'manager_coach' => [
            'title_en' => 'Manager coach', 'title_ar' => 'مدرّب المدير',
            'desc_en' => 'Watches attendance and recognition patterns and tells the manager what to do this week.',
            'desc_ar' => 'يراقب أنماط الحضور والتقدير ويقول للمدير ماذا يفعل هذا الأسبوع.',
            'routes' => ['coach'],
        ],
        'field_proof' => [
            'title_en' => 'Field work proof', 'title_ar' => 'إثبات عمل الميدان',
            'desc_en' => 'Visits with GPS, a photo, the route and a customer signature for field staff.',
            'desc_ar' => 'زيارات بالموقع وصورة والمسار وتوقيع العميل للعاملين في الميدان.',
            'routes' => ['field'],
        ],
        'career_path' => [
            'title_en' => 'Career path', 'title_ar' => 'المسار المهني',
            'desc_en' => 'Levels, skills and a clear next step for each employee, linked to points and promotions.',
            'desc_ar' => 'مستويات ومهارات وخطوة تالية واضحة لكل موظف، مرتبطة بالنقاط والترقيات.',
            'routes' => ['career'],
        ],
    ];
}

/** Feature that owns an API root segment (null = not a feature route). */
function feature_for_route(string $root): ?string {
    foreach (feature_registry() as $key => $f) {
        if (in_array($root, $f['routes'], true)) return $key;
    }
    return null;
}

/** Stored on/off values of one company: key => bool (only keys that were ever set). */
function feature_flags_raw(PDO $pdo, int $companyId): array {
    $s = $pdo->prepare("SELECT feature_key, enabled FROM company_features WHERE company_id = ?");
    $s->execute([$companyId]);
    $out = [];
    foreach ($s->fetchAll() as $r) $out[$r['feature_key']] = (bool)(int)$r['enabled'];
    return $out;
}

/** Full map for a company: every registry key => bool (never set = off). */
function feature_flags(PDO $pdo, int $companyId): array {
    $raw = feature_flags_raw($pdo, $companyId);
    $out = [];
    foreach (feature_registry() as $key => $_) $out[$key] = $raw[$key] ?? false;
    return $out;
}

/** Is the feature on for this company? (default: the caller's company) */
function feature_enabled(PDO $pdo, string $key, ?int $companyId = null): bool {
    static $cache = [];
    $cid = $companyId ?? cid();
    if (!isset($cache[$cid])) {
        try { $cache[$cid] = feature_flags($pdo, $cid); }
        catch (Throwable $e) { $cache[$cid] = []; }          // table missing (migration not run) = everything off
    }
    return $cache[$cid][$key] ?? false;
}

/** Forget cached values (after the owner changed a switch inside the same request). */
function feature_cache_reset(): void { /* feature_enabled keeps a static; the owner API never reads it after writing */ }

/** Stop with 403 when the feature is off for the caller's company. */
function require_feature(PDO $pdo, string $key): void {
    if (!feature_enabled($pdo, $key)) feature_closed_response($key);
}

function feature_closed_response(string $key): void {
    http_response_code(403);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['error' => 'This feature is turned off for your company.', 'code' => 'feature_disabled', 'feature' => $key], JSON_UNESCAPED_UNICODE);
    exit;
}

/** Central gate used by index.php: closes every route that belongs to a feature that is off. */
function feature_gate(PDO $pdo, string $root): void {
    $f = feature_for_route($root);
    if ($f === null) return;
    // the owner dashboard is the owner's own tool: it follows the switch of the owner's HOME company, even while visiting another one
    if ($f === 'group_dashboard') {
        $u = me();
        if (!feature_enabled($pdo, $f, (int)($u['home_company_id'] ?? $u['company_id']))) feature_closed_response($f);
        return;
    }
    // complaints: the owner side may open what was sent up to them even if their own company has the switch off (the handler decides)
    if ($f === 'complaints' && owner_scope($pdo) !== null) return;
    require_feature($pdo, $f);
}

// ------------------------------------------------------------------ who may switch features

/** Is this account a platform owner? (platform_owners is filled only by the server-side setup script, never by the API) */
function platform_owner_check(PDO $pdo, int $userId): bool {
    try {
        $s = $pdo->prepare("SELECT 1 FROM platform_owners WHERE user_id = ? LIMIT 1");
        $s->execute([$userId]);
        return (bool)$s->fetchColumn();
    } catch (Throwable $e) { return false; }
}

/**
 * Companies the caller may switch features for.
 *   ['mode' => 'owner', 'ids' => null]        every company
 *   ['mode' => 'super', 'ids' => [..]]        the companies of the group the caller is Super Admin of
 *   null                                      not allowed
 */
function owner_scope(PDO $pdo): ?array {
    $u = me();
    $uid = (int)$u['id'];
    if (platform_owner_check($pdo, $uid)) return ['mode' => 'owner', 'ids' => null];
    if (function_exists('group_super_admin_of')) {
        $gid = group_super_admin_of($pdo, $uid);
        if ($gid !== null) {
            // companies the owner keeps for himself are not the Super Admin's to switch, unless the owner gave him access
            try {
                $s = $pdo->prepare("SELECT id FROM companies WHERE group_id = ? AND (owner_managed = 0 OR id IN (SELECT company_id FROM company_access WHERE user_id = ?))");
                $s->execute([$gid, $uid]);
            } catch (Throwable $e) {
                $s = $pdo->prepare("SELECT id FROM companies WHERE group_id = ?");
                $s->execute([$gid]);
            }
            return ['mode' => 'super', 'ids' => array_map('intval', $s->fetchAll(PDO::FETCH_COLUMN))];
        }
    }
    return null;
}
