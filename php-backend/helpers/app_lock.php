<?php
/**
 * Single-company apps ("white-label editions").
 *
 * An edition sends `X-App-Id: <id>` with every request. For ids listed below the server only lets people of ONE
 * company use that app: sign-in, activation and every authenticated request of anybody else is refused, and creating
 * new companies through the app is not possible. Requests without the header (the normal multi-company product) are
 * not affected at all.
 *
 *   alanad  ->  the company whose slug is "al-anad" (Al Anad Debt Collection Office)
 *
 * Override on a server with  define('HR_APP_LOCKS', ['alanad' => 'some-slug']);  in config/database.php.
 */

/** Company slug the calling app is locked to, or null when the request is not from a locked edition. */
function app_lock_slug(): ?string {
    // A dedicated single-company server (its own database) sets this in config/database.php: always locked,
    // whatever header arrives, and nobody can register another company.
    // HR_SINGLE_GROUP_SLUG does the same for a whole company group (a holding with companies under it).
    if (defined('HR_SINGLE_GROUP_SLUG')) return (string)HR_SINGLE_GROUP_SLUG;
    if (defined('HR_SINGLE_COMPANY_SLUG')) return (string)HR_SINGLE_COMPANY_SLUG;
    $app = strtolower(trim((string)($_SERVER['HTTP_X_APP_ID'] ?? '')));
    if ($app === '') return null;
    $locks = defined('HR_APP_LOCKS') ? HR_APP_LOCKS : ['alanad' => 'al-anad'];
    return $locks[$app] ?? null;
}

/** Id of the company the app is locked to: null = no lock, 0 = locked but that company does not exist (yet). */
function app_lock_company_id(PDO $pdo): ?int {
    $slug = app_lock_slug();
    if ($slug === null) return null;
    static $cache = [];
    if (!array_key_exists($slug, $cache)) {
        $s = $pdo->prepare("SELECT id FROM companies WHERE slug = ? LIMIT 1");
        $s->execute([$slug]);
        $cache[$slug] = (int)$s->fetchColumn();
    }
    return $cache[$slug];
}

/** Is this company allowed for the calling app? (always true outside locked editions) */
function app_lock_allows(PDO $pdo, int $companyId): bool {
    if (defined('HR_SINGLE_GROUP_SLUG')) {       // every company that belongs to the group is allowed, nobody else
        static $inGroup = [];
        if (!array_key_exists($companyId, $inGroup)) {
            $s = $pdo->prepare("SELECT 1 FROM companies c JOIN company_groups g ON g.id = c.group_id WHERE c.id = ? AND g.slug = ? LIMIT 1");
            $s->execute([$companyId, (string)HR_SINGLE_GROUP_SLUG]);
            $inGroup[$companyId] = (bool)$s->fetchColumn();
        }
        return $inGroup[$companyId];
    }
    $locked = app_lock_company_id($pdo);
    return $locked === null || ($locked > 0 && $locked === $companyId);
}

/** Stop with 403 when a person of another company uses a locked edition. */
function app_lock_assert_company(PDO $pdo, int $companyId): void {
    if (!app_lock_allows($pdo, $companyId)) {
        error_response('This app is only for Al Anad. Please use the ShiftPulse app for your company.', 403);
    }
}
