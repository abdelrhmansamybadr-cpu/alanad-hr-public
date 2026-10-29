<?php
/**
 * Migration 018 — people and departments shared between the companies of a group. Idempotent.
 *
 * Every company stays its own tenant; a share is an explicit, revocable exception made by the HR of the OWNING company:
 *   group_shares.kind = employee   the person is also visible (basic details, read-only) in the target company
 *   group_shares.kind = department the department also exists in the target company: its HR can put their own people in it
 */
if (php_sapi_name() !== 'cli') {
    if (($_GET['t'] ?? '') !== '__MIGRATION_TOKEN__') { http_response_code(403); exit('no'); }
    header('Content-Type: text/plain; charset=utf-8');
    ini_set('display_errors', '1');
    error_reporting(E_ALL);
}
require file_exists(__DIR__ . '/config/database.php') ? __DIR__ . '/config/database.php' : __DIR__ . '/../config/database.php';
$pdo = getDB();

$pdo->exec("CREATE TABLE IF NOT EXISTS `group_shares` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `group_id` INT NOT NULL,
    `kind` ENUM('employee','department') NOT NULL,
    `item_id` INT NOT NULL,
    `source_company_id` INT NOT NULL,
    `target_company_id` INT NOT NULL,
    `created_by` INT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_share` (`kind`, `item_id`, `target_company_id`),
    KEY `idx_share_target` (`target_company_id`, `kind`),
    KEY `idx_share_source` (`source_company_id`, `kind`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
echo "group_shares ready\n";
