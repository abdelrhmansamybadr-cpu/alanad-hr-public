<?php
/**
 * Migration 009 — online meetings (scheduled or "start now"; audio/video call between the invited people). Idempotent.
 *
 *   meetings              the meeting (always inside ONE company)
 *   meeting_participants  who is invited, who is in the call right now, who was removed by the host
 *   meeting_signals       short-lived call set-up messages (offer / answer / ICE / mute ...). The server only relays
 *                         these; the audio and video travel directly between the devices (WebRTC).
 */
if (php_sapi_name() !== 'cli') {
    if (($_GET['t'] ?? '') !== '__MIGRATION_TOKEN__') { http_response_code(403); exit('no'); }
    header('Content-Type: text/plain; charset=utf-8');
    ini_set('display_errors', '1');
    error_reporting(E_ALL);
}
require file_exists(__DIR__ . '/config/database.php') ? __DIR__ . '/config/database.php' : __DIR__ . '/../config/database.php';
$pdo = getDB();

$pdo->exec("CREATE TABLE IF NOT EXISTS `meetings` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `company_id` INT NOT NULL,
    `title` VARCHAR(150) NOT NULL,
    `notes` TEXT NULL,
    `scheduled_at` DATETIME NOT NULL,
    `duration_min` SMALLINT UNSIGNED NOT NULL DEFAULT 30,
    `created_by` INT NOT NULL,
    `status` VARCHAR(12) NOT NULL DEFAULT 'scheduled',
    `started_at` DATETIME NULL,
    `ended_at` DATETIME NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_meetings_company_time` (`company_id`, `scheduled_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$pdo->exec("CREATE TABLE IF NOT EXISTS `meeting_participants` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `meeting_id` INT NOT NULL,
    `user_id` INT NOT NULL,
    `role` VARCHAR(10) NOT NULL DEFAULT 'member',
    `joined_at` DATETIME NULL,
    `left_at` DATETIME NULL,
    `removed` TINYINT(1) NOT NULL DEFAULT 0,
    UNIQUE KEY `uq_meeting_user` (`meeting_id`, `user_id`),
    KEY `idx_participant_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$pdo->exec("CREATE TABLE IF NOT EXISTS `meeting_signals` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `meeting_id` INT NOT NULL,
    `from_user` INT NOT NULL,
    `to_user` INT NOT NULL,
    `type` VARCHAR(24) NOT NULL,
    `payload` MEDIUMTEXT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_signal_to` (`to_user`, `meeting_id`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

echo "Migration 009 finished.\n";
