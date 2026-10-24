<?php
/** Migration 012 — two-step approvals (team head first, then HR) and complaints (head -> HR -> owner). Idempotent. */
if (php_sapi_name() !== 'cli') {
    if (($_GET['t'] ?? '') !== '__MIGRATION_TOKEN__') { http_response_code(403); exit('no'); }
    header('Content-Type: text/plain; charset=utf-8');
    ini_set('display_errors', '1');
    error_reporting(E_ALL);
}
require file_exists(__DIR__ . '/config/database.php') ? __DIR__ . '/config/database.php' : __DIR__ . '/../config/database.php';
$pdo = getDB();

function c_add_col(PDO $pdo, string $table, string $col, string $ddl): void {
    $s = $pdo->prepare("SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?");
    $s->execute([$table, $col]);
    if (!(int)$s->fetchColumn()) { $pdo->exec("ALTER TABLE `$table` ADD COLUMN `$col` $ddl"); echo "added $table.$col\n"; }
}

// Head step of a request: NULL = no head step (old requests / no head), pending, approved, rejected, skipped (HR went past an absent head)
foreach (['leaves', 'requests'] as $t) {
    c_add_col($pdo, $t, 'head_status', "VARCHAR(12) NULL DEFAULT NULL");
    c_add_col($pdo, $t, 'head_by', "INT NULL DEFAULT NULL");
    c_add_col($pdo, $t, 'head_at', "DATETIME NULL DEFAULT NULL");
    c_add_col($pdo, $t, 'head_note', "VARCHAR(500) NULL DEFAULT NULL");
}

$pdo->exec("CREATE TABLE IF NOT EXISTS `complaints` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `author_user_id` INT NOT NULL,
    `author_employee_id` INT NULL,
    `kind` VARCHAR(10) NOT NULL DEFAULT 'member',
    `target_employee_id` INT NULL,
    `subject` VARCHAR(160) NOT NULL,
    `body` TEXT NOT NULL,
    `severity` VARCHAR(10) NOT NULL DEFAULT 'normal',
    `status` VARCHAR(12) NOT NULL DEFAULT 'open',
    `escalated_at` DATETIME NULL,
    `resolved_at` DATETIME NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY `idx_comp_company` (`company_id`, `status`),
    KEY `idx_comp_author` (`author_user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$pdo->exec("CREATE TABLE IF NOT EXISTS `complaint_events` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `complaint_id` INT NOT NULL,
    `actor_user_id` INT NULL,
    `actor_name` VARCHAR(120) NOT NULL DEFAULT '',
    `actor_role` VARCHAR(10) NOT NULL DEFAULT 'head',
    `action` VARCHAR(16) NOT NULL,
    `note` TEXT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_ce_complaint` (`complaint_id`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

echo "migration 012 done\n";
