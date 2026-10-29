<?php
/**
 * Who is signing in? A person can use an e-mail address or a mobile number as their username.
 *
 * Employees that have no e-mail address get an internal placeholder (…@no-email.invalid) so every account still has a
 * unique address internally; it is never shown and never mailed. The mobile number is found through `phone_key`
 * (the last 9 digits), so +966 5x…, 05x… and 5x… all match the same person.
 */

const NO_EMAIL_DOMAIN = 'no-email.invalid';

function phone_digits($raw): string { return preg_replace('/\D+/', '', (string)$raw); }

/** The key a mobile number is looked up by (last 9 digits), or null when it is not a usable number. */
function phone_key($raw): ?string {
    $d = phone_digits($raw);
    if (strlen($d) < 8 || strlen($d) > 15) return null;
    return substr($d, -9);
}

function phone_valid($raw): bool { return phone_key($raw) !== null; }

/** A real address a message can be sent to (valid, and not an internal placeholder). */
function email_is_real($e): bool {
    $e = strtolower(trim((string)$e));
    return $e !== '' && filter_var($e, FILTER_VALIDATE_EMAIL) !== false && !str_ends_with($e, '@' . NO_EMAIL_DOMAIN);
}

/** What the apps may show: placeholders become an empty string. */
function email_public($e): string { return email_is_real($e) ? (string)$e : ''; }

function placeholder_email(PDO $pdo): string {
    for ($i = 0; $i < 8; $i++) {
        $e = 'u' . bin2hex(random_bytes(6)) . '@' . NO_EMAIL_DOMAIN;
        $s = $pdo->prepare("SELECT (SELECT COUNT(*) FROM employees WHERE email = ?) + (SELECT COUNT(*) FROM users WHERE email = ?)");
        $s->execute([$e, $e]);
        if (!(int)$s->fetchColumn()) return $e;
    }
    throw new RuntimeException('Could not create an internal address');
}

/**
 * Turn what the person typed into the account's stored e-mail address. A mobile number is looked up; if it matches
 * nobody (or more than one person) the input is returned unchanged so the normal "not found" answer follows.
 */
function identity_to_email(PDO $pdo, string $input): string {
    $input = strtolower(trim($input));
    if ($input === '' || strpos($input, '@') !== false) return $input;
    $key = phone_key($input);
    if ($key === null) return $input;
    // Compared on the stored number itself (not only phone_key), so a number changed anywhere is always found
    $s = $pdo->prepare(
        "SELECT email FROM users WHERE phone IS NOT NULL AND RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(phone, '+', ''), ' ', ''), '-', ''), '(', ''), ')', ''), '.', ''), 9) = ? AND status != 'disabled'
         UNION SELECT email FROM employees WHERE phone IS NOT NULL AND RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(phone, '+', ''), ' ', ''), '-', ''), '(', ''), ')', ''), '.', ''), 9) = ? AND status != 'inactive' LIMIT 3"
    );
    $s->execute([$key, $key]);
    $emails = array_values(array_unique(array_map('strtolower', $s->fetchAll(PDO::FETCH_COLUMN))));
    return count($emails) === 1 ? $emails[0] : $input;
}

/** Is this mobile number already used by somebody else (another employee, or an account)? Returns that person's name or null. */
function phone_taken(PDO $pdo, $phone, int $exceptEmployeeId = 0): ?string {
    $key = phone_key($phone);
    if ($key === null) return null;
    $s = $pdo->prepare("SELECT CONCAT(first_name, ' ', last_name) FROM employees WHERE phone IS NOT NULL AND RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(phone, '+', ''), ' ', ''), '-', ''), '(', ''), ')', ''), '.', ''), 9) = ? AND id != ? AND status != 'inactive' LIMIT 1");
    $s->execute([$key, $exceptEmployeeId]);
    $n = $s->fetchColumn();
    if ($n !== false) return (string)$n;
    $u = $pdo->prepare("SELECT name FROM users WHERE phone IS NOT NULL AND RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(phone, '+', ''), ' ', ''), '-', ''), '(', ''), ')', ''), '.', ''), 9) = ? AND COALESCE(employee_id, 0) != ? AND status != 'disabled' LIMIT 1");
    $u->execute([$key, $exceptEmployeeId]);
    $n = $u->fetchColumn();
    return $n !== false ? (string)$n : null;
}
