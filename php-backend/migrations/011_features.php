<?php
/** Migration 011 — owner-controlled premium features (switches per company, owners, audit log). Idempotent. */
if (php_sapi_name() !== 'cli') {
    if (($_GET['t'] ?? '') !== '__MIGRATION_TOKEN__') { http_response_code(403); exit('no'); }
    header('Content-Type: text/plain; charset=utf-8');
    ini_set('display_errors', '1');
    error_reporting(E_ALL);
}
require file_exists(__DIR__ . '/config/database.php') ? __DIR__ . '/config/database.php' : __DIR__ . '/../config/database.php';
$pdo = getDB();

$pdo->exec("CREATE TABLE IF NOT EXISTS `platform_owners` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `user_id` INT NOT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_owner_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$pdo->exec("CREATE TABLE IF NOT EXISTS `company_features` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `feature_key` VARCHAR(40) NOT NULL,
    `enabled` TINYINT(1) NOT NULL DEFAULT 0,
    `updated_by` INT NULL,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_company_feature` (`company_id`, `feature_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$pdo->exec("CREATE TABLE IF NOT EXISTS `feature_audit` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `feature_key` VARCHAR(40) NOT NULL,
    `enabled` TINYINT(1) NOT NULL,
    `actor_user_id` INT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_audit_company` (`company_id`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

/** add a column only when it is missing */
function f_add_col(PDO $pdo, string $table, string $col, string $ddl): void {
    $s = $pdo->prepare("SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?");
    $s->execute([$table, $col]);
    if (!$s->fetchColumn()) { $pdo->exec("ALTER TABLE `$table` ADD COLUMN `$col` $ddl"); echo "  + $table.$col\n"; }
}

// --- local laws: which country's law pack the company follows + its editable figures
f_add_col($pdo, 'companies', 'law_country', "VARCHAR(2) NULL");
f_add_col($pdo, 'companies', 'law_params', "MEDIUMTEXT NULL");

// --- fair decisions: an adverse decision (rejected leave/request, lost point...) that an employee disputes
$pdo->exec("CREATE TABLE IF NOT EXISTS `decision_disputes` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `employee_id` INT NOT NULL,
    `kind` VARCHAR(20) NOT NULL,
    `ref_id` INT NOT NULL,
    `message` TEXT NOT NULL,
    `status` ENUM('open','upheld','reversed') NOT NULL DEFAULT 'open',
    `response` TEXT NULL,
    `responded_by` INT NULL,
    `responded_at` DATETIME NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_dispute_ref` (`company_id`, `kind`, `ref_id`),
    KEY `idx_dispute_emp` (`company_id`, `employee_id`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// --- field work proof: visits with GPS, photo, route and customer signature
$pdo->exec("CREATE TABLE IF NOT EXISTS `field_visits` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `employee_id` INT NOT NULL,
    `customer_name` VARCHAR(150) NOT NULL,
    `customer_phone` VARCHAR(40) NULL,
    `address` VARCHAR(255) NULL,
    `purpose` VARCHAR(255) NULL,
    `status` ENUM('active','done','cancelled') NOT NULL DEFAULT 'active',
    `started_at` DATETIME NOT NULL,
    `ended_at` DATETIME NULL,
    `start_lat` DECIMAL(10,7) NULL, `start_lng` DECIMAL(10,7) NULL,
    `end_lat` DECIMAL(10,7) NULL, `end_lng` DECIMAL(10,7) NULL,
    `distance_m` INT NOT NULL DEFAULT 0,
    `photo_file` VARCHAR(120) NULL,
    `signature_file` VARCHAR(120) NULL,
    `signed_name` VARCHAR(150) NULL,
    `notes` TEXT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_field_emp` (`company_id`, `employee_id`, `started_at`),
    KEY `idx_field_day` (`company_id`, `started_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
$pdo->exec("CREATE TABLE IF NOT EXISTS `field_points` (
    `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `visit_id` INT NOT NULL,
    `lat` DECIMAL(10,7) NOT NULL, `lng` DECIMAL(10,7) NOT NULL,
    `recorded_at` DATETIME NOT NULL,
    KEY `idx_fp_visit` (`visit_id`, `recorded_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// --- career path: levels, skills, and who has which skill at which level
$pdo->exec("CREATE TABLE IF NOT EXISTS `career_levels` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `rank_no` INT NOT NULL,
    `name_en` VARCHAR(100) NOT NULL,
    `name_ar` VARCHAR(100) NULL,
    `min_months` INT NOT NULL DEFAULT 0,
    `min_points` INT NOT NULL DEFAULT 0,
    `skills` TEXT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_level_rank` (`company_id`, `rank_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
$pdo->exec("CREATE TABLE IF NOT EXISTS `career_skills` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `name_en` VARCHAR(100) NOT NULL,
    `name_ar` VARCHAR(100) NULL,
    UNIQUE KEY `uq_skill_name` (`company_id`, `name_en`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
$pdo->exec("CREATE TABLE IF NOT EXISTS `employee_skills` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `employee_id` INT NOT NULL,
    `skill_id` INT NOT NULL,
    `proficiency` TINYINT NOT NULL DEFAULT 1,
    `verified_by` INT NULL,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_emp_skill` (`employee_id`, `skill_id`),
    KEY `idx_es_company` (`company_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
f_add_col($pdo, 'employees', 'career_level_id', "INT NULL");

echo "Migration 011 finished (switches, owners, audit log + data tables of the premium features).\n";
