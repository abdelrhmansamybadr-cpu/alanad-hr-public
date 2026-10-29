<?php
/**
 * Migration 019 - employees.work_status, decided by the first digit of the ID number. Idempotent.
 *   own_sponsor | other_sponsor (ID starts with 2, HR chooses) | irregular (any other first digit)
 */
if (php_sapi_name() !== 'cli') {
    if (($_GET['t'] ?? '') !== '__MIGRATION_TOKEN__') { http_response_code(403); exit('no'); }
    header('Content-Type: text/plain; charset=utf-8');
    ini_set('display_errors', '1');
    error_reporting(E_ALL);
}
require file_exists(__DIR__ . '/config/database.php') ? __DIR__ . '/config/database.php' : __DIR__ . '/../config/database.php';
$pdo = getDB();

$s = $pdo->prepare("SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'employees' AND COLUMN_NAME = 'work_status'");
$s->execute();
if (!(int)$s->fetchColumn()) { $pdo->exec("ALTER TABLE `employees` ADD COLUMN `work_status` VARCHAR(20) NULL DEFAULT NULL"); echo "added employees.work_status\n"; }
echo "done\n";
