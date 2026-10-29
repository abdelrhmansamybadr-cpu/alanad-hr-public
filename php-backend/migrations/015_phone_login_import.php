<?php
/**
 * Migration 015 — sign in with a mobile number, invitations by e-mail or SMS, and the employee fields of the
 * residence/ID sheet (nationality, ID number, bank account, residence expiry). Idempotent.
 *
 *  - employees.phone_key / users.phone_key: the last 9 digits of the mobile number, used to find the account when a
 *    person signs in with the number instead of an e-mail address.
 *  - employees without an e-mail get an internal placeholder address ending in @no-email.invalid (never shown, never mailed).
 */
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
function c_add_index(PDO $pdo, string $table, string $name, string $cols): void {
    $s = $pdo->prepare("SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?");
    $s->execute([$table, $name]);
    if (!(int)$s->fetchColumn()) { $pdo->exec("ALTER TABLE `$table` ADD INDEX `$name` ($cols)"); echo "index $table.$name\n"; }
}

c_add_col($pdo, 'employees', 'phone_key', "VARCHAR(12) NULL DEFAULT NULL");
c_add_col($pdo, 'users', 'phone_key', "VARCHAR(12) NULL DEFAULT NULL");
c_add_index($pdo, 'employees', 'idx_emp_phone_key', '`phone_key`');
c_add_index($pdo, 'users', 'idx_usr_phone_key', '`phone_key`');

c_add_col($pdo, 'employees', 'nationality', "VARCHAR(60) NULL DEFAULT NULL");
c_add_col($pdo, 'employees', 'id_number', "VARCHAR(40) NULL DEFAULT NULL");
c_add_col($pdo, 'employees', 'bank_iban', "VARCHAR(40) NULL DEFAULT NULL");
c_add_col($pdo, 'employees', 'iqama_expiry', "DATE NULL DEFAULT NULL");
c_add_col($pdo, 'employees', 'iqama_renew_months', "INT NULL DEFAULT NULL");
c_add_col($pdo, 'employees', 'import_notes', "TEXT NULL");
c_add_col($pdo, 'employees', 'invited_at', "DATETIME NULL DEFAULT NULL");
c_add_col($pdo, 'employees', 'invited_via', "VARCHAR(10) NULL DEFAULT NULL");

// Fill the keys for the numbers that are already stored
$digits = function (?string $raw): ?string {
    $d = preg_replace('/\D+/', '', (string)$raw);
    if (strlen($d) < 8 || strlen($d) > 15) return null;
    return substr($d, -9);
};
foreach (['employees', 'users'] as $t) {
    $rows = $pdo->query("SELECT id, phone FROM `$t` WHERE phone IS NOT NULL AND phone != '' AND phone_key IS NULL")->fetchAll();
    $up = $pdo->prepare("UPDATE `$t` SET phone_key = ? WHERE id = ?");
    $n = 0;
    foreach ($rows as $r) { $k = $digits($r['phone']); if ($k !== null) { $up->execute([$k, $r['id']]); $n++; } }
    echo "phone keys for $t: $n\n";
}
echo "migration 015 done\n";
