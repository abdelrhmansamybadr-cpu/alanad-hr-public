<?php
/**
 * Setup script: make an account a PLATFORM OWNER (can switch premium features on/off for every company).
 * Run once through the deploy helper (token protected), then it is deleted from the server.
 *
 *   ?t=TOKEN&email=owner@example.com[&name=Full Name][&company=slug]
 *
 * - account exists  -> it is marked as owner (its password is not touched)
 * - account missing -> it is created as company admin of `company` (default: the first company) with a random
 *                      password that is printed ONCE here, so the owner can sign in and change it.
 * Idempotent. Needs migration 011 (platform_owners).
 */
if (php_sapi_name() !== 'cli') {
    if (($_GET['t'] ?? '') !== '__MIGRATION_TOKEN__') { http_response_code(403); exit('no'); }
    header('Content-Type: text/plain; charset=utf-8');
    ini_set('display_errors', '1');
    error_reporting(E_ALL);
    $email = strtolower(trim((string)($_GET['email'] ?? '')));
    $name  = trim((string)($_GET['name'] ?? 'Platform Owner'));
    $slug  = trim((string)($_GET['company'] ?? ''));
} else {
    $email = strtolower(trim((string)($argv[1] ?? '')));
    $name  = trim((string)($argv[2] ?? 'Platform Owner'));
    $slug  = trim((string)($argv[3] ?? ''));
}
require file_exists(__DIR__ . '/config/database.php') ? __DIR__ . '/config/database.php' : __DIR__ . '/../config/database.php';
$pdo = getDB();

if (!filter_var($email, FILTER_VALIDATE_EMAIL)) { echo "A valid email is required.\n"; exit(1); }

$s = $pdo->prepare("SELECT id FROM users WHERE email = ? LIMIT 1");
$s->execute([$email]);
$uid = (int)$s->fetchColumn();
$password = null;

if (!$uid) {
    if ($slug !== '') {
        $c = $pdo->prepare("SELECT id FROM companies WHERE slug = ? LIMIT 1");
        $c->execute([$slug]);
        $companyId = (int)$c->fetchColumn();
    } else {
        $companyId = (int)$pdo->query("SELECT id FROM companies ORDER BY id LIMIT 1")->fetchColumn();
    }
    if (!$companyId) { echo "No company found to attach the owner account to.\n"; exit(1); }
    $password = substr(str_replace(['+', '/', '='], '', base64_encode(random_bytes(12))), 0, 12) . '9a!';
    $pdo->prepare("INSERT INTO users (company_id, name, email, password_hash, role, status, created_at) VALUES (?, ?, ?, ?, 'hr_admin', 'active', NOW())")
        ->execute([$companyId, $name, $email, password_hash($password, PASSWORD_BCRYPT)]);
    $uid = (int)$pdo->lastInsertId();
    echo "Account created for $email (company admin of company #$companyId).\n";
} else {
    echo "Account $email already exists (password untouched).\n";
}

$pdo->prepare("INSERT IGNORE INTO platform_owners (user_id) VALUES (?)")->execute([$uid]);
echo "OWNER: $email (user #$uid) can now switch features on and off.\n";
if ($password !== null) echo "ONE-TIME PASSWORD (shown only now): $password\n";
