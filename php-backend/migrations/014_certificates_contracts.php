<?php
/** Migration 014 — leaving certificates (designer, issue, e-mail, scheduled account closing) and employee contracts with expiry alarms. Idempotent. */
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

// Contract of every employee: type, start, end (NULL end = no end date) and the length in months used to fill the end date
c_add_col($pdo, 'employees', 'contract_type', "VARCHAR(20) NULL DEFAULT NULL");
c_add_col($pdo, 'employees', 'contract_start', "DATE NULL DEFAULT NULL");
c_add_col($pdo, 'employees', 'contract_end', "DATE NULL DEFAULT NULL");
c_add_col($pdo, 'employees', 'contract_months', "INT NULL DEFAULT NULL");

$pdo->exec("CREATE TABLE IF NOT EXISTS `contract_settings` (
    `company_id` INT NOT NULL PRIMARY KEY,
    `remind_days` VARCHAR(60) NOT NULL DEFAULT '30,14,7,1',
    `notify_hr` TINYINT(1) NOT NULL DEFAULT 1,
    `notify_manager` TINYINT(1) NOT NULL DEFAULT 1,
    `notify_employee` TINYINT(1) NOT NULL DEFAULT 0,
    `email_hr` TINYINT(1) NOT NULL DEFAULT 0,
    `remind_expired` TINYINT(1) NOT NULL DEFAULT 1,
    `last_run` DATE NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$pdo->exec("CREATE TABLE IF NOT EXISTS `contract_alerts` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `employee_id` INT NOT NULL,
    `contract_end` DATE NOT NULL,
    `days_before` INT NOT NULL,
    `sent_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_contract_alert` (`company_id`, `employee_id`, `contract_end`, `days_before`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// Images the HR team uploads for certificates: backgrounds, logos, signatures, stamps (files live in uploads/certificates, served only to HR)
$pdo->exec("CREATE TABLE IF NOT EXISTS `certificate_assets` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `name` VARCHAR(160) NOT NULL DEFAULT '',
    `file_path` VARCHAR(255) NOT NULL,
    `mime_type` VARCHAR(60) NOT NULL,
    `width` INT NOT NULL DEFAULT 0,
    `height` INT NOT NULL DEFAULT 0,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_ca_company` (`company_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// A reusable design: size, background colour/image, optional frame and the blocks (text with {placeholders}, images) in `layout` (JSON text)
$pdo->exec("CREATE TABLE IF NOT EXISTS `certificate_templates` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `name` VARCHAR(120) NOT NULL,
    `kind` VARCHAR(20) NOT NULL DEFAULT 'experience',
    `lang` VARCHAR(2) NOT NULL DEFAULT 'en',
    `width` INT NOT NULL DEFAULT 1123,
    `height` INT NOT NULL DEFAULT 794,
    `bg_color` VARCHAR(9) NOT NULL DEFAULT '#ffffff',
    `bg_asset_id` INT NULL,
    `layout` MEDIUMTEXT NOT NULL,
    `created_by` INT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY `idx_ct_company` (`company_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// One row per certificate: draft (serial reserved while the person designs it) -> issued (image + PDF stored, e-mailed)
$pdo->exec("CREATE TABLE IF NOT EXISTS `certificates` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `employee_id` INT NOT NULL,
    `template_id` INT NULL,
    `serial` VARCHAR(30) NOT NULL,
    `kind` VARCHAR(20) NOT NULL DEFAULT 'experience',
    `title` VARCHAR(160) NOT NULL DEFAULT '',
    `status` VARCHAR(10) NOT NULL DEFAULT 'draft',
    `width` INT NOT NULL DEFAULT 0,
    `height` INT NOT NULL DEFAULT 0,
    `image_path` VARCHAR(255) NULL,
    `pdf_path` VARCHAR(255) NULL,
    `leave_date` DATE NULL,
    `data_json` TEXT NULL,
    `emailed_to` VARCHAR(255) NULL,
    `emailed_at` DATETIME NULL,
    `issued_by` INT NULL,
    `issued_at` DATETIME NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_cert_serial` (`company_id`, `serial`),
    KEY `idx_cert_employee` (`company_id`, `employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// Account closing planned after a certificate: pending -> done (or cancelled). close_at is in the company's local time.
$pdo->exec("CREATE TABLE IF NOT EXISTS `exit_closures` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `employee_id` INT NOT NULL,
    `certificate_id` INT NULL,
    `close_at` DATETIME NOT NULL,
    `status` VARCHAR(10) NOT NULL DEFAULT 'pending',
    `leave_date` DATE NULL,
    `reason` VARCHAR(255) NULL,
    `set_by` INT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `done_at` DATETIME NULL,
    KEY `idx_ec_due` (`company_id`, `status`, `close_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

echo "migration 014 done\n";
