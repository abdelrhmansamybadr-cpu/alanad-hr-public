<?php
/** Migration 004 — peer kudos. Idempotent. */
if (php_sapi_name() !== 'cli') {
    if (($_GET['t'] ?? '') !== '__MIGRATION_TOKEN__') { http_response_code(403); exit('no'); }
    header('Content-Type: text/plain; charset=utf-8');
    ini_set('display_errors', '1');
    error_reporting(E_ALL);
}
require file_exists(__DIR__ . '/config/database.php') ? __DIR__ . '/config/database.php' : __DIR__ . '/../config/database.php';
$pdo = getDB();

$pdo->exec("CREATE TABLE IF NOT EXISTS `kudos` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `from_employee_id` INT NOT NULL,
    `to_employee_id` INT NOT NULL,
    `badge` VARCHAR(30) NOT NULL DEFAULT 'thanks',
    `message` VARCHAR(500) NOT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_kudos_company` (`company_id`, `id`),
    KEY `idx_kudos_to` (`to_employee_id`),
    KEY `idx_kudos_from` (`from_employee_id`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
echo "Migration 004 finished.\n";
