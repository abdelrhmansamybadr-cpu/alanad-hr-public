<?php
/**
 * Migration 008 — company groups (a holding company with several separate companies under it). Idempotent.
 *
 * Every company stays a fully separate tenant (its own company_id on every row). The group layer only adds:
 *   company_groups   the holding ("Al Anad")
 *   companies.group_id / ceo_user_id
 *   group_admins     super admins of a group (may enter every company of the group)
 *   company_access   extra access of one HR user to another company of the same group (level, modules, read-only)
 *   sessions.active_company_id   which company a signed-in user is currently working in
 */
if (php_sapi_name() !== 'cli') {
    if (($_GET['t'] ?? '') !== '__MIGRATION_TOKEN__') { http_response_code(403); exit('no'); }
    header('Content-Type: text/plain; charset=utf-8');
    ini_set('display_errors', '1');
    error_reporting(E_ALL);
}
require file_exists(__DIR__ . '/config/database.php') ? __DIR__ . '/config/database.php' : __DIR__ . '/../config/database.php';
$pdo = getDB();

function g_has_col(PDO $pdo, string $t, string $c): bool {
    $s = $pdo->prepare("SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?");
    $s->execute([$t, $c]);
    return (bool)$s->fetchColumn();
}

$pdo->exec("CREATE TABLE IF NOT EXISTS `company_groups` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(255) NOT NULL,
    `slug` VARCHAR(100) NOT NULL UNIQUE,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

if (!g_has_col($pdo, 'companies', 'group_id')) {
    $pdo->exec("ALTER TABLE `companies` ADD COLUMN `group_id` INT NULL, ADD INDEX `idx_companies_group` (`group_id`)");
    echo "  + companies.group_id\n";
}
if (!g_has_col($pdo, 'companies', 'ceo_user_id')) {
    $pdo->exec("ALTER TABLE `companies` ADD COLUMN `ceo_user_id` INT NULL");
    echo "  + companies.ceo_user_id\n";
}

$pdo->exec("CREATE TABLE IF NOT EXISTS `group_admins` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `group_id` INT NOT NULL,
    `user_id` INT NOT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_group_admin` (`group_id`, `user_id`),
    KEY `idx_group_admin_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$pdo->exec("CREATE TABLE IF NOT EXISTS `company_access` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `user_id` INT NOT NULL,
    `company_id` INT NOT NULL,
    `level` ENUM('full','custom') NOT NULL DEFAULT 'full',
    `modules` TEXT NULL,
    `read_only` TINYINT(1) NOT NULL DEFAULT 0,
    `granted_by` INT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_access_user_company` (`user_id`, `company_id`),
    KEY `idx_access_company` (`company_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

if (!g_has_col($pdo, 'sessions', 'active_company_id')) {
    $pdo->exec("ALTER TABLE `sessions` ADD COLUMN `active_company_id` INT NULL");
    echo "  + sessions.active_company_id\n";
}

echo "Migration 008 finished.\n";
