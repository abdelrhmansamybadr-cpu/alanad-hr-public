<?php
/**
 * Migration 016 — who may record attendance, and how. Idempotent.
 *  employees.attendance_mode        company (the company rules, default) | rule (one chosen rule) | free (no place check: an exception)
 *  employees.attendance_rule_id     the rule used when mode = rule
 *  employees.attendance_blocked     HR blocked this person from recording attendance
 *  attendance_attempts              check-ins tried away from the workplace (so HR can decide to block)
 */
if (php_sapi_name() !== 'cli') {
    if (($_GET['t'] ?? '') !== '__MIGRATION_TOKEN__') { http_response_code(403); exit('no'); }
    header('Content-Type: text/plain; charset=utf-8');
    ini_set('display_errors', '1');
    error_reporting(E_ALL);
}
require file_exists(__DIR__ . '/config/database.php') ? __DIR__ . '/config/database.php' : __DIR__ . '/../config/database.php';
$pdo = getDB();

function a_add_col(PDO $pdo, string $table, string $col, string $ddl): void {
    $s = $pdo->prepare("SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?");
    $s->execute([$table, $col]);
    if (!(int)$s->fetchColumn()) { $pdo->exec("ALTER TABLE `$table` ADD COLUMN `$col` $ddl"); echo "added $table.$col\n"; }
}
a_add_col($pdo, 'employees', 'attendance_mode', "VARCHAR(10) NOT NULL DEFAULT 'company'");
a_add_col($pdo, 'employees', 'attendance_rule_id', "INT NULL DEFAULT NULL");
a_add_col($pdo, 'employees', 'attendance_blocked', "TINYINT(1) NOT NULL DEFAULT 0");
a_add_col($pdo, 'employees', 'attendance_block_reason', "VARCHAR(255) NULL DEFAULT NULL");
a_add_col($pdo, 'employees', 'attendance_blocked_at', "DATETIME NULL DEFAULT NULL");

$pdo->exec("CREATE TABLE IF NOT EXISTS `attendance_attempts` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `employee_id` INT NOT NULL,
    `action` VARCHAR(20) NOT NULL,
    `lat` DECIMAL(10,8) NULL,
    `lng` DECIMAL(11,8) NULL,
    `distance_m` INT NULL,
    `message` VARCHAR(255) NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_att_attempt_emp` (`company_id`, `employee_id`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
echo "migration 016 done\n";
