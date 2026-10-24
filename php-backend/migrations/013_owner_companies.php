<?php
/** Migration 013 — companies created by the owner can be owner-managed: the group Super Admin sees them only when the owner gives access. Idempotent. */
if (php_sapi_name() !== 'cli') {
    if (($_GET['t'] ?? '') !== '__MIGRATION_TOKEN__') { http_response_code(403); exit('no'); }
    header('Content-Type: text/plain; charset=utf-8');
    ini_set('display_errors', '1');
    error_reporting(E_ALL);
}
require file_exists(__DIR__ . '/config/database.php') ? __DIR__ . '/config/database.php' : __DIR__ . '/../config/database.php';
$pdo = getDB();

$s = $pdo->prepare("SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'companies' AND COLUMN_NAME = 'owner_managed'");
$s->execute();
if (!(int)$s->fetchColumn()) {
    $pdo->exec("ALTER TABLE `companies` ADD COLUMN `owner_managed` TINYINT(1) NOT NULL DEFAULT 0");
    echo "added companies.owner_managed\n";
}
echo "migration 013 done\n";
