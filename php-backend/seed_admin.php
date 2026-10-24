<?php
/**
 * Admin Seeder Script
 *
 * Run this script ONCE after importing database.sql to create/update the
 * admin user with a properly generated PHP password hash.
 *
 * Usage (via browser): https://yourdomain.com/api/seed_admin.php?secret=CHANGE_ME
 * Usage (via CLI):     php seed_admin.php
 *
 * DELETE THIS FILE after running it!
 */

// Simple security token to prevent unauthorized access
define('SEED_SECRET', 'CHANGE_ME_BEFORE_UPLOADING');

// Check secret if running via HTTP
if (php_sapi_name() !== 'cli') {
    if (($_GET['secret'] ?? '') !== SEED_SECRET) {
        http_response_code(403);
        die(json_encode(['error' => 'Forbidden. Provide ?secret=YOUR_SECRET']));
    }
}

require_once __DIR__ . '/config/database.php';

$pdo = getDB();

// Admin credentials — change these!
$adminName     = 'HR Admin';
$adminEmail    = 'admin@company.com';
$adminPassword = 'admin123';

$hash = password_hash($adminPassword, PASSWORD_BCRYPT);

// Upsert the admin user
$stmt = $pdo->prepare(
    "INSERT INTO users (name, email, password_hash, role, status, created_at)
     VALUES (?, ?, ?, 'hr_admin', 'active', NOW())
     ON DUPLICATE KEY UPDATE
        name = VALUES(name),
        password_hash = VALUES(password_hash),
        role = 'hr_admin',
        status = 'active'"
);
$stmt->execute([$adminName, $adminEmail, $hash]);

echo json_encode([
    'success'  => true,
    'message'  => 'Admin user created/updated successfully',
    'email'    => $adminEmail,
    'password' => $adminPassword,
    'note'     => 'DELETE THIS FILE immediately after running it!',
]);
