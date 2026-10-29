<?php
/**
 * Migration 017 — attendance rules can require a wired (cable) network instead of Wi-Fi. Idempotent.
 *  attendance_rules.network_type   wifi (default) | wired
 *  attendance_rules.wired_gateway  for a wired rule: the gateway (router) address of the company cable network
 */
if (php_sapi_name() !== 'cli') {
    if (($_GET['t'] ?? '') !== '__MIGRATION_TOKEN__') { http_response_code(403); exit('no'); }
    header('Content-Type: text/plain; charset=utf-8');
    ini_set('display_errors', '1');
    error_reporting(E_ALL);
}
require file_exists(__DIR__ . '/config/database.php') ? __DIR__ . '/config/database.php' : __DIR__ . '/../config/database.php';
$pdo = getDB();

function w_add_col(PDO $pdo, string $table, string $col, string $ddl): void {
    $s = $pdo->prepare("SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?");
    $s->execute([$table, $col]);
    if (!(int)$s->fetchColumn()) { $pdo->exec("ALTER TABLE `$table` ADD COLUMN `$col` $ddl"); echo "added $table.$col\n"; }
}
w_add_col($pdo, 'attendance_rules', 'network_type', "VARCHAR(10) NOT NULL DEFAULT 'wifi'");
w_add_col($pdo, 'attendance_rules', 'wired_gateway', "VARCHAR(64) NULL DEFAULT NULL");
echo "done\n";
