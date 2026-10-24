<?php
/** Migration 007 — passkeys (Windows Hello / Touch ID / phone unlock sign-in). Idempotent. */
if (php_sapi_name() !== 'cli') {
    if (($_GET['t'] ?? '') !== '__MIGRATION_TOKEN__') { http_response_code(403); exit('no'); }
    header('Content-Type: text/plain; charset=utf-8');
    ini_set('display_errors', '1');
    error_reporting(E_ALL);
}
require file_exists(__DIR__ . '/config/database.php') ? __DIR__ . '/config/database.php' : __DIR__ . '/../config/database.php';
$pdo = getDB();

// One row per registered device credential. The public key is stored as PEM; the private key never leaves the device.
$pdo->exec("CREATE TABLE IF NOT EXISTS `passkeys` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `user_id` INT NOT NULL,
    `credential_id` TEXT NOT NULL,
    `credential_hash` CHAR(64) NOT NULL,
    `public_key` TEXT NOT NULL,
    `alg` INT NOT NULL,
    `sign_count` INT UNSIGNED NOT NULL DEFAULT 0,
    `label` VARCHAR(120) NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_used_at` DATETIME NULL,
    UNIQUE KEY `uq_passkey_cred` (`credential_hash`),
    KEY `idx_passkey_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// One-time challenges (5 minutes), consumed on first use.
$pdo->exec("CREATE TABLE IF NOT EXISTS `webauthn_challenges` (
    `challenge` VARCHAR(64) NOT NULL PRIMARY KEY,
    `purpose` VARCHAR(10) NOT NULL,
    `user_id` INT NULL,
    `expires_at` DATETIME NOT NULL,
    KEY `idx_wa_exp` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

echo "Migration 007 finished.\n";
