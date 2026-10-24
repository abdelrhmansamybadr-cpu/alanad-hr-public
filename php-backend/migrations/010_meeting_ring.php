<?php
/** Migration 010 — "ringing" for meetings: remember who dismissed the incoming-meeting alert. Idempotent. */
if (php_sapi_name() !== 'cli') {
    if (($_GET['t'] ?? '') !== '__MIGRATION_TOKEN__') { http_response_code(403); exit('no'); }
    header('Content-Type: text/plain; charset=utf-8');
    ini_set('display_errors', '1');
    error_reporting(E_ALL);
}
require file_exists(__DIR__ . '/config/database.php') ? __DIR__ . '/config/database.php' : __DIR__ . '/../config/database.php';
$pdo = getDB();

$s = $pdo->prepare("SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meeting_participants' AND COLUMN_NAME = 'dismissed_at'");
$s->execute();
if (!$s->fetchColumn()) {
    $pdo->exec("ALTER TABLE `meeting_participants` ADD COLUMN `dismissed_at` DATETIME NULL");
    echo "  + meeting_participants.dismissed_at\n";
}
echo "Migration 010 finished.\n";
