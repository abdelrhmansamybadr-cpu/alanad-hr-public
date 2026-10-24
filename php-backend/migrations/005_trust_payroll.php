<?php
/**
 * Migration 005 — attendance trust (device id, security flags), payroll loans, signing secret
 * for printable payslip links. Idempotent.
 */
if (php_sapi_name() !== 'cli') {
    if (($_GET['t'] ?? '') !== '__MIGRATION_TOKEN__') { http_response_code(403); exit('no'); }
    header('Content-Type: text/plain; charset=utf-8');
    ini_set('display_errors', '1');
    error_reporting(E_ALL);
}
require file_exists(__DIR__ . '/config/database.php') ? __DIR__ . '/config/database.php' : __DIR__ . '/../config/database.php';
$pdo = getDB();

function m5_has_col(PDO $pdo, string $t, string $c): bool {
    $s = $pdo->prepare("SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?");
    $s->execute([$t, $c]);
    return (bool)$s->fetchColumn();
}
function m5_add_col(PDO $pdo, string $t, string $c, string $ddl): void {
    if (!m5_has_col($pdo, $t, $c)) {
        $pdo->exec("ALTER TABLE `$t` ADD COLUMN `$c` $ddl");
        echo "  + $t.$c\n";
    }
}

echo "== attendance trust\n";
m5_add_col($pdo, 'attendance', 'device_id', 'VARCHAR(64) NULL');
m5_add_col($pdo, 'attendance', 'security_flags', 'VARCHAR(120) NULL');

echo "== payroll loans\n";
$pdo->exec("CREATE TABLE IF NOT EXISTS `payroll_loans` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `employee_id` INT NOT NULL,
    `title` VARCHAR(150) NOT NULL,
    `amount` DECIMAL(12,2) NOT NULL,
    `installment` DECIMAL(12,2) NOT NULL,
    `status` ENUM('active','cancelled') NOT NULL DEFAULT 'active',
    `start_month` CHAR(7) NOT NULL,
    `created_by` INT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_loans_emp` (`company_id`, `employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

echo "== password resets\n";
$pdo->exec("CREATE TABLE IF NOT EXISTS `password_resets` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `user_id` INT NOT NULL,
    `code_hash` CHAR(64) NOT NULL,
    `attempts` INT NOT NULL DEFAULT 0,
    `expires_at` DATETIME NOT NULL,
    `used_at` DATETIME NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_pr_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

echo "== signing secret\n";
$pdo->exec("CREATE TABLE IF NOT EXISTS `app_secrets` (
    `name` VARCHAR(40) NOT NULL PRIMARY KEY,
    `value` VARCHAR(128) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

echo "Migration 005 finished.\n";
