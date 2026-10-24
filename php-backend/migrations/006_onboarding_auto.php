<?php
/**
 * Migration 006 — onboarding steps that the SYSTEM completes (not the employee):
 * an `auto_key` on templates/tasks and an events table the app writes to when the employee really did the step.
 * Idempotent.
 */
if (php_sapi_name() !== 'cli') {
    if (($_GET['t'] ?? '') !== '__MIGRATION_TOKEN__') { http_response_code(403); exit('no'); }
    header('Content-Type: text/plain; charset=utf-8');
    ini_set('display_errors', '1');
    error_reporting(E_ALL);
}
require file_exists(__DIR__ . '/config/database.php') ? __DIR__ . '/config/database.php' : __DIR__ . '/../config/database.php';
$pdo = getDB();

function m6_has_col(PDO $pdo, string $t, string $c): bool {
    $s = $pdo->prepare("SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?");
    $s->execute([$t, $c]);
    return (bool)$s->fetchColumn();
}
foreach (['onboarding_templates', 'onboarding_tasks'] as $t) {
    if (!m6_has_col($pdo, $t, 'auto_key')) {
        $pdo->exec("ALTER TABLE `$t` ADD COLUMN `auto_key` VARCHAR(30) NULL");
        echo "  + $t.auto_key\n";
    }
}

$pdo->exec("CREATE TABLE IF NOT EXISTS `onboarding_events` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `employee_id` INT NOT NULL,
    `ev_key` VARCHAR(30) NOT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_obe` (`employee_id`, `ev_key`),
    KEY `idx_obe_company` (`company_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// the eight starter steps get their key by title (companies that edited a title simply keep a manual step)
$map = [
    'Read and sign your employment contract' => 'contract',
    'Complete your personal details' => 'details',
    'Upload your ID and required documents' => 'documents',
    'Add the employee to payroll' => 'payroll',
    'Meet your manager and team' => 'team',
    'Read the company policies' => 'policies',
    'Turn on notifications and check in once from the app' => 'checkin',
];
foreach (['onboarding_templates', 'onboarding_tasks'] as $t) {
    $u = $pdo->prepare("UPDATE `$t` SET auto_key = ? WHERE title = ? AND auto_key IS NULL");
    foreach ($map as $title => $key) $u->execute([$key, $title]);
}
echo "Migration 006 finished.\n";
