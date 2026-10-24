<?php
/** Migration 003 — onboarding checklists. Idempotent. */
if (php_sapi_name() !== 'cli') {
    if (($_GET['t'] ?? '') !== '__MIGRATION_TOKEN__') { http_response_code(403); exit('no'); }
    header('Content-Type: text/plain; charset=utf-8');
    ini_set('display_errors', '1');
    error_reporting(E_ALL);
}
require file_exists(__DIR__ . '/config/database.php') ? __DIR__ . '/config/database.php' : __DIR__ . '/../config/database.php';
$pdo = getDB();

$pdo->exec("CREATE TABLE IF NOT EXISTS `onboarding_templates` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `title` VARCHAR(200) NOT NULL,
    `description` TEXT NULL,
    `owner` ENUM('employee','hr') NOT NULL DEFAULT 'employee',
    `due_days` INT NOT NULL DEFAULT 7,
    `sort_order` INT NOT NULL DEFAULT 0,
    `is_active` TINYINT(1) NOT NULL DEFAULT 1,
    KEY `idx_obt_company` (`company_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$pdo->exec("CREATE TABLE IF NOT EXISTS `onboarding_tasks` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `employee_id` INT NOT NULL,
    `title` VARCHAR(200) NOT NULL,
    `description` TEXT NULL,
    `owner` ENUM('employee','hr') NOT NULL DEFAULT 'employee',
    `due_date` DATE NULL,
    `sort_order` INT NOT NULL DEFAULT 0,
    `done` TINYINT(1) NOT NULL DEFAULT 0,
    `done_at` DATETIME NULL,
    `done_by` INT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_obk_emp` (`employee_id`, `done`),
    KEY `idx_obk_company` (`company_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
echo "Migration 003 finished.\n";
