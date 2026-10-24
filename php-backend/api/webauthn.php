<?php
/**
 * Passkeys — sign in with Windows Hello / fingerprint / face / device PIN.
 *
 *   GET    /auth/webauthn                    own status {registered, registeredAt, count}      (signed in)
 *   DELETE /auth/webauthn                    remove all own passkeys                           (signed in)
 *   POST   /auth/webauthn/register-options   challenge for adding this device                 (signed in)
 *   POST   /auth/webauthn/register-verify    save the new passkey                              (signed in)
 *   POST   /auth/webauthn/login-options      {email?} challenge; no e-mail = pick from the device's passkeys
 *   POST   /auth/webauthn/login-verify       {email?, assertionResponse} -> same answer as /auth/login
 *
 * The request normalizer rewrites camelCase keys to snake_case, which would break the browser's
 * field names (clientDataJSON ...), so the verify endpoints read the raw request body themselves.
 */
require_once __DIR__ . '/../helpers/webauthn.php';

const WA_MAX_PASSKEYS = 5;

function wa_raw_body(): array {
    $d = json_decode((string)file_get_contents('php://input'), true);
    return is_array($d) ? $d : [];
}

function handle_auth_webauthn(string $sub, string $method, array $body, PDO $pdo): void {
    switch ($sub) {
        case '':
            hr_set_user(require_auth());
            if ($method === 'GET') wa_status($pdo);
            if ($method === 'DELETE') wa_remove($pdo);
            error_response('Method not allowed', 405);
            break;
        case 'register-options':
            if ($method !== 'POST') error_response('Method not allowed', 405);
            hr_set_user(require_auth());
            wa_register_options($pdo);
            break;
        case 'register-verify':
            if ($method !== 'POST') error_response('Method not allowed', 405);
            hr_set_user(require_auth());
            wa_register_verify($pdo);
            break;
        case 'login-options':
            if ($method !== 'POST') error_response('Method not allowed', 405);
            wa_login_options($body, $pdo);
            break;
        case 'login-verify':
            if ($method !== 'POST') error_response('Method not allowed', 405);
            wa_login_verify($pdo);
            break;
        default:
            error_response('Not found', 404);
    }
}

function wa_cred_hash(string $credIdB64u): string {
    return hash('sha256', $credIdB64u);
}

function wa_status(PDO $pdo): void {
    $s = $pdo->prepare("SELECT COUNT(*) AS n, MIN(created_at) AS first_at FROM passkeys WHERE user_id = ?");
    $s->execute([(int)me()['id']]);
    $r = $s->fetch();
    json_response([
        'registered'    => (int)$r['n'] > 0,
        'registered_at' => $r['first_at'] ? substr($r['first_at'], 0, 10) : null,
        'count'         => (int)$r['n'],
    ]);
}

function wa_remove(PDO $pdo): void {
    $pdo->prepare("DELETE FROM passkeys WHERE user_id = ?")->execute([(int)me()['id']]);
    json_response(['removed' => true]);
}

function wa_register_options(PDO $pdo): void {
    $u = me();
    $s = $pdo->prepare("SELECT credential_id FROM passkeys WHERE user_id = ?");
    $s->execute([(int)$u['id']]);
    $existing = $s->fetchAll(PDO::FETCH_COLUMN);
    if (count($existing) >= WA_MAX_PASSKEYS) error_response('You already registered the maximum number of devices.', 422);
    json_response([
        'rp'                     => ['name' => 'Al Anad HR', 'id' => wa_rp_id()],
        'user'                   => ['id' => wa_b64u_encode('u' . (int)$u['id']), 'name' => (string)$u['email'], 'displayName' => (string)($u['name'] ?? $u['email'])],
        'challenge'              => wa_challenge_create($pdo, 'reg', (int)$u['id']),
        'pubKeyCredParams'       => [['type' => 'public-key', 'alg' => -7], ['type' => 'public-key', 'alg' => -257]],
        'timeout'                => 60000,
        'attestation'            => 'none',
        'excludeCredentials'     => array_map(fn($id) => ['type' => 'public-key', 'id' => $id], $existing),
        'authenticatorSelection' => ['authenticatorAttachment' => 'platform', 'residentKey' => 'preferred', 'requireResidentKey' => false, 'userVerification' => 'required'],
    ]);
}

function wa_register_verify(PDO $pdo): void {
    $u = me();
    $att = wa_raw_body();
    try {
        $rpId = wa_rp_id();
        $challenge = wa_response_challenge($att['response'] ?? [], 'webauthn.create', $rpId);
        if (!wa_challenge_consume($pdo, $challenge, 'reg', (int)$u['id'])) throw new RuntimeException('challenge expired or unknown');
        [$credId, $pem, $alg, $count] = wa_verify_registration($att, $rpId);
    } catch (Throwable $e) {
        error_log('webauthn register failed: ' . $e->getMessage());
        error_response('Passkey registration failed. Please try again.', 400);
    }
    $n = $pdo->prepare("SELECT COUNT(*) FROM passkeys WHERE user_id = ?");
    $n->execute([(int)$u['id']]);
    if ((int)$n->fetchColumn() >= WA_MAX_PASSKEYS) error_response('You already registered the maximum number of devices.', 422);
    try {
        $pdo->prepare("INSERT INTO passkeys (user_id, credential_id, credential_hash, public_key, alg, sign_count, label) VALUES (?, ?, ?, ?, ?, ?, ?)")
            ->execute([(int)$u['id'], $credId, wa_cred_hash($credId), $pem, $alg, $count, substr((string)($att['label'] ?? 'This device'), 0, 120)]);
    } catch (PDOException $e) {
        error_response('This device is already registered.', 409);
    }
    json_response(['registered' => true], 201);
}

function wa_login_options(array $body, PDO $pdo): void {
    $email = strtolower(trim((string)($body['email'] ?? '')));
    $allow = [];
    if ($email !== '') {
        $s = $pdo->prepare("SELECT p.credential_id FROM passkeys p JOIN users u ON u.id = p.user_id WHERE u.email = ?");
        $s->execute([$email]);
        $ids = $s->fetchAll(PDO::FETCH_COLUMN);
        if (!$ids) error_response('No passkey registered for this account', 404);
        $allow = array_map(fn($id) => ['type' => 'public-key', 'id' => $id], $ids);
    }
    json_response([
        'challenge'        => wa_challenge_create($pdo, 'auth', null),
        'rpId'             => wa_rp_id(),
        'timeout'          => 60000,
        'userVerification' => 'required',
        'allowCredentials' => $allow,
    ]);
}

function wa_login_verify(PDO $pdo): void {
    $in = wa_raw_body();
    $assertion = is_array($in['assertionResponse'] ?? null) ? $in['assertionResponse'] : [];
    $email = strtolower(trim((string)($in['email'] ?? '')));
    $ipKey = 'passkeyip:' . auth_client_ip();
    if (throttle_count($pdo, $ipKey, 15) >= 20) error_response('Too many failed attempts. Please try again in 15 minutes.', 429);

    $user = null;
    try {
        $rpId = wa_rp_id();
        $s = $pdo->prepare(
            "SELECT p.id AS pk_id, p.public_key, p.sign_count, u.*, c.status AS company_status
             FROM passkeys p JOIN users u ON u.id = p.user_id JOIN companies c ON c.id = u.company_id
             WHERE p.credential_hash = ? LIMIT 1"
        );
        $s->execute([wa_cred_hash((string)($assertion['id'] ?? ''))]);
        $cred = $s->fetch();
        if (!$cred) throw new RuntimeException('unknown credential');
        if ($email !== '' && strtolower((string)$cred['email']) !== $email) throw new RuntimeException('credential belongs to another account');
        $challenge = wa_response_challenge($assertion['response'] ?? [], 'webauthn.get', $rpId);
        if (!wa_challenge_consume($pdo, $challenge, 'auth')) throw new RuntimeException('challenge expired or unknown');
        $newCount = wa_verify_assertion($assertion, $cred, $rpId);
        $user = $cred;
    } catch (Throwable $e) {
        error_log('webauthn login failed: ' . $e->getMessage());
        throttle_hit($pdo, $ipKey);
        error_response('Passkey sign-in failed. Use your password instead.', 401);
    }
    if ($user['status'] !== 'active') error_response('Your account is not active. Please contact HR.', 403);
    if ($user['company_status'] !== 'active') error_response('This company account is suspended.', 403);

    $pdo->prepare("UPDATE passkeys SET sign_count = ?, last_used_at = NOW() WHERE id = ?")->execute([$newCount, $user['pk_id']]);
    unset($user['pk_id'], $user['public_key'], $user['sign_count']);
    auth_session_response($pdo, $user);
}
