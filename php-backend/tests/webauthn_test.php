<?php
/**
 * Offline test of helpers/webauthn.php — no database or browser needed.
 * Plays the part of an authenticator (real OpenSSL keys) and checks that good messages pass
 * and tampered / replayed / wrong-site ones are refused.   php php-backend/tests/webauthn_test.php
 */
require __DIR__ . '/../helpers/webauthn.php';

$pass = 0; $fail = 0;
function check(string $name, bool $ok): void {
    global $pass, $fail;
    echo ($ok ? "  ok   " : "  FAIL ") . $name . "\n";
    $ok ? $pass++ : $fail++;
}
function throws(callable $f): bool { try { $f(); return false; } catch (Throwable $e) { return true; } }

// ---- tiny CBOR writer (what a real authenticator produces)
function cbor_head(int $major, int $n): string {
    if ($n < 24) return chr(($major << 5) | $n);
    if ($n < 256) return chr(($major << 5) | 24) . chr($n);
    return chr(($major << 5) | 25) . pack('n', $n);
}
function cbor($v): string {
    if (is_int($v)) return $v >= 0 ? cbor_head(0, $v) : cbor_head(1, -1 - $v);
    if (is_string($v)) return str_starts_with($v, "\x01BIN") ? cbor_head(2, strlen($v) - 4) . substr($v, 4) : cbor_head(3, strlen($v)) . $v;
    $o = cbor_head(5, count($v));
    foreach ($v as $k => $x) $o .= cbor($k) . cbor($x);
    return $o;
}
function bin(string $s): string { return "\x01BIN" . $s; }          // mark a PHP string as a CBOR byte string

$rp = 'hr.quadrocloud.net';
$origin = 'https://' . $rp;

function make_key(string $type) {
    return $type === 'ec'
        ? openssl_pkey_new(['curve_name' => 'prime256v1', 'private_key_type' => OPENSSL_KEYTYPE_EC])
        : openssl_pkey_new(['private_key_bits' => 2048, 'private_key_type' => OPENSSL_KEYTYPE_RSA]);
}
function cose_of($key, string $type): array {
    $d = openssl_pkey_get_details($key);
    if ($type === 'ec') return [1 => 2, 3 => -7, -1 => 1, -2 => bin($d['ec']['x']), -3 => bin($d['ec']['y'])];
    return [1 => 3, 3 => -257, -1 => bin($d['rsa']['n']), -2 => bin($d['rsa']['e'])];
}
function client_data(string $type, string $challenge, string $origin): string {
    return json_encode(['type' => $type, 'challenge' => $challenge, 'origin' => $origin, 'crossOrigin' => false]);
}
function make_registration($key, string $type, string $credId, string $rp, string $challenge, string $origin, int $flags = 0x45): array {
    $authData = hash('sha256', $rp, true) . chr($flags) . pack('N', 0) . str_repeat("\0", 16)
        . pack('n', strlen($credId)) . $credId . cbor(cose_of($key, $type));
    $att = cbor(['fmt' => 'none', 'attStmt' => [], 'authData' => bin($authData)]);
    return ['id' => wa_b64u_encode($credId), 'rawId' => wa_b64u_encode($credId), 'type' => 'public-key',
        'response' => ['clientDataJSON' => wa_b64u_encode(client_data('webauthn.create', $challenge, $origin)), 'attestationObject' => wa_b64u_encode($att)]];
}
function make_assertion($key, string $credId, string $rp, string $challenge, string $origin, int $count, int $flags = 0x05): array {
    $cd = client_data('webauthn.get', $challenge, $origin);
    $authData = hash('sha256', $rp, true) . chr($flags) . pack('N', $count);
    openssl_sign($authData . hash('sha256', $cd, true), $sig, $key, OPENSSL_ALGO_SHA256);
    return ['id' => wa_b64u_encode($credId), 'type' => 'public-key',
        'response' => ['clientDataJSON' => wa_b64u_encode($cd), 'authenticatorData' => wa_b64u_encode($authData), 'signature' => wa_b64u_encode($sig)]];
}

foreach (['ec' => 'ES256', 'rsa' => 'RS256 (Windows Hello TPM)'] as $type => $label) {
    echo "== $label\n";
    $key = make_key($type);
    $credId = random_bytes(32);
    $reg = make_registration($key, $type, $credId, $rp, 'chal-1', $origin);
    [$id, $pem, $alg, $cnt] = wa_verify_registration($reg, $rp);
    check('registration accepted', $id === wa_b64u_encode($credId) && $cnt === 0);
    check('public key converted to PEM', openssl_pkey_get_public($pem) !== false);
    $cred = ['public_key' => $pem, 'sign_count' => 0];

    check('sign-in accepted, counter returned', wa_verify_assertion(make_assertion($key, $credId, $rp, 'c2', $origin, 1), $cred, $rp) === 1);
    check('replayed counter refused', throws(fn() => wa_verify_assertion(make_assertion($key, $credId, $rp, 'c3', $origin, 1), ['public_key' => $pem, 'sign_count' => 1], $rp)));
    check('other key refused', throws(fn() => wa_verify_assertion(make_assertion(make_key($type), $credId, $rp, 'c4', $origin, 2), $cred, $rp)));
    check('phishing origin refused', throws(fn() => wa_verify_assertion(make_assertion($key, $credId, $rp, 'c5', 'https://evil.example', 2), $cred, $rp)));
    check('other site (rpId hash) refused', throws(fn() => wa_verify_assertion(make_assertion($key, $credId, 'evil.example', 'c6', $origin, 2), $cred, $rp)));
    check('no user verification refused', throws(fn() => wa_verify_assertion(make_assertion($key, $credId, $rp, 'c7', $origin, 2, 0x01), $cred, $rp)));
    $bad = make_assertion($key, $credId, $rp, 'c8', $origin, 2);
    $bad['response']['clientDataJSON'] = wa_b64u_encode(client_data('webauthn.get', 'changed', $origin));
    check('tampered client data refused', throws(fn() => wa_verify_assertion($bad, $cred, $rp)));
    check('registration with wrong origin refused', throws(fn() => wa_verify_registration(make_registration($key, $type, $credId, $rp, 'c9', 'https://evil.example'), $rp)));
    check('registration without user verification refused', throws(fn() => wa_verify_registration(make_registration($key, $type, $credId, $rp, 'c10', $origin, 0x41), $rp)));
    $mismatch = make_registration($key, $type, $credId, $rp, 'c11', $origin);
    $mismatch['id'] = wa_b64u_encode(random_bytes(32));
    check('credential id mismatch refused', throws(fn() => wa_verify_registration($mismatch, $rp)));
}
echo "== helpers\n";
check('origin: https rp ok', wa_origin_ok('https://hr.quadrocloud.net', 'hr.quadrocloud.net'));
check('origin: http refused', !wa_origin_ok('http://hr.quadrocloud.net', 'hr.quadrocloud.net'));
check('origin: localhost dev port ok', wa_origin_ok('http://localhost:5173', 'localhost'));
check('garbage cbor refused', throws(fn() => wa_cbor_decode("\xff\xff")));
check('base64url round trip', wa_b64u_decode(wa_b64u_encode("\x00\xfb\xff")) === "\x00\xfb\xff");

echo "\n$pass passed, $fail failed\n";
exit($fail ? 1 : 0);
