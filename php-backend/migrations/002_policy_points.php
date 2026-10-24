<?php
/**
 * Migration 002 — automatic attendance policy, reward points, promotions,
 * department heads, request payloads, audit log, payroll breakdown.
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

function mig_has_col(PDO $pdo, string $t, string $c): bool {
    $s = $pdo->prepare("SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?");
    $s->execute([$t, $c]);
    return (bool)$s->fetchColumn();
}
function mig_add_col(PDO $pdo, string $t, string $c, string $ddl): void {
    if (!mig_has_col($pdo, $t, $c)) {
        $pdo->exec("ALTER TABLE `$t` ADD COLUMN `$c` $ddl");
        echo "  + $t.$c\n";
    }
}
function mig_has_index(PDO $pdo, string $t, string $i): bool {
    $s = $pdo->prepare("SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?");
    $s->execute([$t, $i]);
    return (bool)$s->fetchColumn();
}

echo "== attendance\n";
foreach ([
    'early_leave_minutes' => 'INT NOT NULL DEFAULT 0',
    'out_zone_minutes'    => 'INT NOT NULL DEFAULT 0',
    'overtime_minutes'    => 'INT NOT NULL DEFAULT 0',
    'last_ping_at'        => 'DATETIME NULL',
    'last_inside_at'      => 'DATETIME NULL',
    'last_ping_inside'    => 'TINYINT(1) NULL',
    'check_in_inside'     => 'TINYINT(1) NULL',
    'check_out_inside'    => 'TINYINT(1) NULL',
    'flags'               => 'VARCHAR(120) NULL',
    'edited_by'           => 'INT NULL',
    'closed'              => 'TINYINT(1) NOT NULL DEFAULT 0',
] as $c => $ddl) { mig_add_col($pdo, 'attendance', $c, $ddl); }
if (!mig_has_index($pdo, 'attendance', 'idx_att_emp_date')) {
    $pdo->exec("ALTER TABLE `attendance` ADD INDEX `idx_att_emp_date` (`employee_id`, `date`)");
}

echo "== attendance rules (several locations, Wi-Fi BSSID, any/all)\n";
mig_add_col($pdo, 'attendance_rules', 'match_mode', "VARCHAR(5) NOT NULL DEFAULT 'any'");
mig_add_col($pdo, 'attendance_rules', 'wifi_bssid', 'VARCHAR(50) NULL');

echo "== companies: policies\n";
mig_add_col($pdo, 'companies', 'attendance_policy', 'TEXT NULL');
mig_add_col($pdo, 'companies', 'points_config', 'TEXT NULL');
mig_add_col($pdo, 'companies', 'payroll_policy', 'TEXT NULL');

echo "== requests payload\n";
mig_add_col($pdo, 'requests', 'payload', 'TEXT NULL');

echo "== departments head\n";
mig_add_col($pdo, 'departments', 'head_employee_id', 'INT NULL');

echo "== employees: offboarding\n";
mig_add_col($pdo, 'employees', 'termination_date', 'DATE NULL');
mig_add_col($pdo, 'employees', 'termination_reason', 'TEXT NULL');
mig_add_col($pdo, 'employees', 'grade', 'VARCHAR(50) NULL');

echo "== payroll breakdown\n";
mig_add_col($pdo, 'payroll', 'breakdown', 'TEXT NULL');

echo "== reward points\n";
$pdo->exec("CREATE TABLE IF NOT EXISTS `points_ledger` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `employee_id` INT NOT NULL,
    `date` DATE NOT NULL,
    `color` ENUM('green','red','black','none') NOT NULL,
    `reason` VARCHAR(40) NOT NULL DEFAULT '',
    `source` ENUM('auto','manual') NOT NULL DEFAULT 'auto',
    `auto_key` VARCHAR(10) NULL,
    `note` VARCHAR(255) NULL,
    `voided` TINYINT(1) NOT NULL DEFAULT 0,
    `created_by` INT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_points_auto` (`employee_id`, `auto_key`),
    KEY `idx_points_company` (`company_id`, `date`),
    KEY `idx_points_emp` (`employee_id`, `date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$pdo->exec("CREATE TABLE IF NOT EXISTS `employee_levels` (
    `employee_id` INT NOT NULL PRIMARY KEY,
    `company_id` INT NOT NULL,
    `level` INT NOT NULL DEFAULT 0,
    `processed_until` DATE NULL,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY `idx_levels_company` (`company_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

echo "== promotions\n";
$pdo->exec("CREATE TABLE IF NOT EXISTS `promotions` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `employee_id` INT NOT NULL,
    `type` VARCHAR(20) NOT NULL DEFAULT 'promotion',
    `from_position` VARCHAR(255) NULL,
    `to_position` VARCHAR(255) NULL,
    `from_salary` DECIMAL(10,2) NULL,
    `to_salary` DECIMAL(10,2) NULL,
    `from_department_id` INT NULL,
    `to_department_id` INT NULL,
    `effective_date` DATE NOT NULL,
    `applied` TINYINT(1) NOT NULL DEFAULT 1,
    `note` TEXT NULL,
    `created_by` INT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_promo_emp` (`employee_id`, `effective_date`),
    KEY `idx_promo_company` (`company_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

echo "== audit log\n";
$pdo->exec("CREATE TABLE IF NOT EXISTS `audit_log` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `user_id` INT NULL,
    `user_name` VARCHAR(255) NULL,
    `action` VARCHAR(60) NOT NULL,
    `entity` VARCHAR(40) NOT NULL,
    `entity_id` INT NULL,
    `details` TEXT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_audit_company` (`company_id`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

echo "\nMigration 002 finished.\n";
