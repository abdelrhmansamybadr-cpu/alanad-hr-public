<?php
/**
 * Migration 001 — multi-company support + new modules.
 *
 * Idempotent: safe to run more than once. Run it through the web once
 * (upload, open with the one-time token, then delete it from the server).
 *
 * Existing data becomes company #1.
 */
if (php_sapi_name() !== 'cli') {
    // The deploy step replaces __MIGRATION_TOKEN__ with a random value.
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

echo "== companies\n";
$pdo->exec("CREATE TABLE IF NOT EXISTS `companies` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(255) NOT NULL,
    `slug` VARCHAR(100) NOT NULL UNIQUE,
    `logo_url` TEXT NULL,
    `primary_color` VARCHAR(9) NOT NULL DEFAULT '#00617A',
    `accent_color` VARCHAR(9) NOT NULL DEFAULT '#C88453',
    `timezone` VARCHAR(64) NOT NULL DEFAULT 'Africa/Cairo',
    `currency` VARCHAR(8) NOT NULL DEFAULT 'EGP',
    `weekend_days` VARCHAR(50) NOT NULL DEFAULT 'fri,sat',
    `language` VARCHAR(5) NOT NULL DEFAULT 'en',
    `late_grace_minutes` INT NOT NULL DEFAULT 15,
    `modules` TEXT NULL,
    `plan` VARCHAR(30) NOT NULL DEFAULT 'free',
    `status` ENUM('active','suspended') NOT NULL DEFAULT 'active',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
$pdo->exec("INSERT IGNORE INTO companies (id, name, slug) VALUES (1, 'Demo Company', 'demo')");

echo "== company_id on tenant tables\n";
$tenantTables = [
    'users', 'departments', 'shifts', 'employees', 'attendance', 'attendance_rules',
    'leaves', 'leave_policy', 'payroll', 'jobs', 'applications', 'reviews',
    'announcements', 'required_document_types', 'employee_documents',
];
foreach ($tenantTables as $t) {
    if (!mig_has_col($pdo, $t, 'company_id')) {
        $pdo->exec("ALTER TABLE `$t` ADD COLUMN `company_id` INT NOT NULL DEFAULT 1");
        $pdo->exec("ALTER TABLE `$t` ADD INDEX `idx_{$t}_company` (`company_id`)");
        // Existing rows are company 1; from now on every insert must name its company.
        $pdo->exec("ALTER TABLE `$t` ALTER COLUMN `company_id` DROP DEFAULT");
        echo "  + $t.company_id\n";
    }
}

echo "== new columns\n";
mig_add_col($pdo, 'users', 'last_login_at', 'DATETIME NULL');
foreach ([
    'birth_date'      => 'DATE NULL',
    'gender'          => 'VARCHAR(10) NULL',
    'address'         => 'TEXT NULL',
    'emergency_name'  => 'VARCHAR(255) NULL',
    'emergency_phone' => 'VARCHAR(50) NULL',
    'manager_id'      => 'INT NULL',
] as $c => $ddl) { mig_add_col($pdo, 'employees', $c, $ddl); }
foreach ([
    'check_in_lat'  => 'DECIMAL(10,8) NULL',
    'check_in_lng'  => 'DECIMAL(11,8) NULL',
    'check_out_lat' => 'DECIMAL(10,8) NULL',
    'check_out_lng' => 'DECIMAL(11,8) NULL',
    'source'        => "VARCHAR(20) NOT NULL DEFAULT 'manual'",
    'note'          => 'TEXT NULL',
    'late_minutes'  => 'INT NOT NULL DEFAULT 0',
] as $c => $ddl) { mig_add_col($pdo, 'attendance', $c, $ddl); }
foreach ([
    'reviewed_by' => 'INT NULL',
    'reviewed_at' => 'DATETIME NULL',
    'review_note' => 'TEXT NULL',
] as $c => $ddl) { mig_add_col($pdo, 'leaves', $c, $ddl); }

echo "== new tables\n";
$pdo->exec("CREATE TABLE IF NOT EXISTS `notifications` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `user_id` INT NOT NULL,
    `type` VARCHAR(50) NOT NULL,
    `title` VARCHAR(255) NOT NULL,
    `body` TEXT NULL,
    `data` TEXT NULL,
    `read_at` DATETIME NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_notif_user` (`user_id`, `read_at`),
    KEY `idx_notif_company` (`company_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$pdo->exec("CREATE TABLE IF NOT EXISTS `holidays` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `name` VARCHAR(255) NOT NULL,
    `date` DATE NOT NULL,
    UNIQUE KEY `uq_holiday` (`company_id`, `date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$pdo->exec("CREATE TABLE IF NOT EXISTS `leave_types` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `code` VARCHAR(50) NOT NULL,
    `name` VARCHAR(100) NOT NULL,
    `days_per_year` INT NOT NULL DEFAULT 0,
    `paid` TINYINT(1) NOT NULL DEFAULT 1,
    `color` VARCHAR(9) NOT NULL DEFAULT '#00617A',
    `is_active` TINYINT(1) NOT NULL DEFAULT 1,
    UNIQUE KEY `uq_leave_type` (`company_id`, `code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$pdo->exec("CREATE TABLE IF NOT EXISTS `requests` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `employee_id` INT NOT NULL,
    `type` VARCHAR(50) NOT NULL,
    `title` VARCHAR(255) NOT NULL,
    `description` TEXT NULL,
    `amount` DECIMAL(10,2) NULL,
    `status` ENUM('pending','approved','rejected','cancelled') NOT NULL DEFAULT 'pending',
    `reviewed_by` INT NULL,
    `reviewed_at` DATETIME NULL,
    `review_note` TEXT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_requests_company` (`company_id`, `status`),
    KEY `idx_requests_employee` (`employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");


echo "== enums / security tables\n";
$pdo->exec("ALTER TABLE `leaves` MODIFY `status` ENUM('pending','approved','rejected','cancelled') NOT NULL DEFAULT 'pending'");

$pdo->exec("CREATE TABLE IF NOT EXISTS `invitations` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `employee_id` INT NOT NULL,
    `purpose` ENUM('activate','reset') NOT NULL,
    `code_hash` CHAR(64) NOT NULL,
    `expires_at` DATETIME NOT NULL,
    `used_at` DATETIME NULL,
    `attempts` INT NOT NULL DEFAULT 0,
    `created_by` INT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_inv_employee` (`employee_id`, `purpose`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$pdo->exec("CREATE TABLE IF NOT EXISTS `throttle` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `k` VARCHAR(190) NOT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_throttle` (`k`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

echo "== default leave types for companies that have none\n";
$defaults = [
    ['annual',  'Annual leave',  21, 1, '#00617A'],
    ['sick',    'Sick leave',    10, 1, '#EF4444'],
    ['casual',  'Casual leave',   6, 1, '#F59E0B'],
    ['unpaid',  'Unpaid leave',   0, 0, '#64748B'],
];
$ins = $pdo->prepare("INSERT IGNORE INTO leave_types (company_id, code, name, days_per_year, paid, color) VALUES (?,?,?,?,?,?)");
foreach ($pdo->query("SELECT id FROM companies")->fetchAll(PDO::FETCH_COLUMN) as $cid) {
    $has = $pdo->prepare("SELECT COUNT(*) FROM leave_types WHERE company_id = ?");
    $has->execute([$cid]);
    if ((int)$has->fetchColumn() === 0) {
        foreach ($defaults as $d) { $ins->execute(array_merge([$cid], $d)); }
        echo "  seeded company $cid\n";
    }
}

echo "\nMigration 001 finished.\n";
foreach ($pdo->query("SHOW TABLES")->fetchAll(PDO::FETCH_COLUMN) as $t) { echo " - $t\n"; }
