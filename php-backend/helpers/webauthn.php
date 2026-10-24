<?php
/**
 * WebAuthn / passkeys (Windows Hello, Touch ID, phone unlock) — registration and sign-in verification.
 *
 * Supports ES256 (-7) and RS256 (-257), which covers Windows Hello, Apple and Android.
 * Attestation is not checked (we ask for "none"): we only need to bind a public key to the
 * account, the key itself is then verified on every sign-in.
 */

// ------------------------------------------------------------------ encoding

function wa_b64u_encode(string $bin): string {
    return rtrim(strtr(base64_encode($bin), '+/', '-_'), '=');
}

function wa_b64u_decode(string $s): string {
    $s = strtr($s, '-_', '+/');
    if ($pad = strlen($s) % 4) $s .= str_repeat('=', 4 - $pad);
    $bin = base64_decode($s, true);
    if ($bin === false) throw new RuntimeException('bad base64url');
    return $bin;
}

// ----------------------------------------------------------- relying party

/** The site id the browser binds credentials to. Never taken blindly from the Host header. */
function wa_rp_id(): string {
    if (defined('HR_WEBAUTHN_RP_ID')) return HR_WEBAUTHN_RP_ID;
    $host = strtolower(preg_replace('/:\d+$/', '', (string)($_SERVER['HTTP_HOST'] ?? '')));
    return in_array($host, ['hr.quadrocloud.net', 'localhost'], true) ? $host : 'hr.quadrocloud.net';
}

function wa_origin_ok(string $origin, string $rpId): bool {
    if ($origin === 'https://' . $rpId) return true;
    return $rpId === 'localhost' && (bool)preg_match('#^http://localhost(:\d{1,5})?$#', $origin);
}

// -------------------------------------------------------------------- CBOR

/** Minimal CBOR reader: ints, byte/text strings, arrays, maps, booleans, null. */
function wa_cbor_decode(string $d, int &$pos = 0, int $depth = 0) {
    if ($depth > 8 || $pos >= strlen($d)) throw new RuntimeException('bad cbor');
    $b = ord($d[$pos++]);
    $major = $b >> 5;
    $info = $b & 31;
    if ($major === 7) {
        if ($info === 20) return false;
        if ($info === 21) return true;
        if ($info === 22) return null;
        throw new RuntimeException('unsupported cbor simple value');
    }
    if ($info < 24) {
        $len = $info;
    } elseif ($info >= 24 && $info <= 27) {
        $n = [24 => 1, 25 => 2, 26 => 4, 27 => 8][$info];
        if ($pos + $n > strlen($d)) throw new RuntimeException('bad cbor');
        $raw = substr($d, $pos, $n);
        $pos += $n;
        $len = $n === 1 ? ord($raw) : ($n === 2 ? unpack('n', $raw)[1] : ($n === 4 ? unpack('N', $raw)[1] : unpack('J', $raw)[1]));
    } else {
        throw new RuntimeException('unsupported cbor length');
    }
    switch ($major) {
        case 0: return $len;
        case 1: return -1 - $len;
        case 2:
        case 3:
            if ($len < 0 || $pos + $len > strlen($d)) throw new RuntimeException('bad cbor');
            $s = substr($d, $pos, $len);
            $pos += $len;
            return $s;
        case 4:
            if ($len > 64) throw new RuntimeException('cbor array too large');
            $out = [];
            for ($i = 0; $i < $len; $i++) $out[] = wa_cbor_decode($d, $pos, $depth + 1);
            return $out;
        case 5:
            if ($len > 64) throw new RuntimeException('cbor map too large');
            $out = [];
            for ($i = 0; $i < $len; $i++) {
                $k = wa_cbor_decode($d, $pos, $depth + 1);
                $out[$k] = wa_cbor_decode($d, $pos, $depth + 1);
            }
            return $out;
    }
    throw new RuntimeException('unsupported cbor type');
}

// ----------------------------------------------------- public key -> PEM

function wa_der(int $tag, string $content): string {
    $n = strlen($content);
    $len = $n < 128 ? chr($n) : (($n < 256) ? "\x81" . chr($n) : "\x82" . pack('n', $n));
    return chr($tag) . $len . $content;
}

function wa_der_int(string $bin): string {
    $bin = ltrim($bin, "\x00");
    if ($bin === '' || (ord($bin[0]) & 0x80)) $bin = "\x00" . $bin;
    return wa_der(0x02, $bin);
}

function wa_pem(string $spkiDer): string {
    return "-----BEGIN PUBLIC KEY-----\n" . chunk_split(base64_encode($spkiDer), 64, "\n") . "-----END PUBLIC KEY-----\n";
}

/** COSE public key (ES256 or RS256) -> [pem, alg]. */
function wa_cose_to_pem(array $cose): array {
    $alg = $cose[3] ?? null;
    if ($alg === -7 && ($cose[1] ?? null) === 2 && ($cose[-1] ?? null) === 1) {
        $x = $cose[-2] ?? ''; $y = $cose[-3] ?? '';
        if (strlen($x) !== 32 || strlen($y) !== 32) throw new RuntimeException('bad EC key');
        $spki = hex2bin('3059301306072a8648ce3d020106082a8648ce3d030107034200') . "\x04" . $x . $y;
        return [wa_pem($spki), -7];
    }
    if ($alg === -257 && ($cose[1] ?? null) === 3) {
        $n = $cose[-1] ?? ''; $e = $cose[-2] ?? '';
        if (strlen($n) < 128 || $e === '') throw new RuntimeException('bad RSA key');
        $rsaKey = wa_der(0x30, wa_der_int($n) . wa_der_int($e));
        $algId = wa_der(0x30, hex2bin('06092a864886f70d0101010500'));
        return [wa_pem(wa_der(0x30, $algId . wa_der(0x03, "\x00" . $rsaKey))), -257];
    }
    throw new RuntimeException('unsupported key type');
}

// ------------------------------------------------------------ challenges

function wa_challenge_create(PDO $pdo, string $purpose, ?int $userId): string {
    $challenge = wa_b64u_encode(random_bytes(32));
    $pdo->prepare("INSERT INTO webauthn_challenges (challenge, purpose, user_id, expires_at) VALUES (?, ?, ?, (NOW() + INTERVAL 5 MINUTE))")
        ->execute([$challenge, $purpose, $userId]);
    if (mt_rand(1, 20) === 1) $pdo->exec("DELETE FROM webauthn_challenges WHERE expires_at < NOW()");
    return $challenge;
}

/** Use a challenge exactly once. For registration the challenge must belong to `$userId`. */
function wa_challenge_consume(PDO $pdo, string $challenge, string $purpose, ?int $userId = null): bool {
    $s = $pdo->prepare("SELECT user_id FROM webauthn_challenges WHERE challenge = ? AND purpose = ? AND expires_at > NOW()");
    $s->execute([$challenge, $purpose]);
    $row = $s->fetch();
    if (!$row) return false;
    if ($userId !== null && (int)$row['user_id'] !== $userId) return false;
    $d = $pdo->prepare("DELETE FROM webauthn_challenges WHERE challenge = ?");
    $d->execute([$challenge]);
    return $d->rowCount() === 1;      // two parallel requests cannot both win
}

// ---------------------------------------------------------- verification

/** Decode and check clientDataJSON; returns [challenge, raw bytes]. */
function wa_read_client_data(array $response, string $type, string $rpId): array {
    $raw = wa_b64u_decode((string)($response['clientDataJSON'] ?? ''));
    $cd = json_decode($raw, true);
    if (!is_array($cd) || ($cd['type'] ?? '') !== $type) throw new RuntimeException('wrong clientData type');
    if (!wa_origin_ok((string)($cd['origin'] ?? ''), $rpId)) throw new RuntimeException('origin not allowed');
    if (!empty($cd['crossOrigin'])) throw new RuntimeException('cross-origin request');
    $challenge = (string)($cd['challenge'] ?? '');
    if ($challenge === '') throw new RuntimeException('no challenge');
    return [$challenge, $raw];
}

/** The challenge a browser response answers (so the caller can look it up before verifying). */
function wa_response_challenge(array $response, string $type, string $rpId): string {
    return wa_read_client_data($response, $type, $rpId)[0];
}

/** Check the fixed part of authenticatorData; returns [flags, signCount]. */
function wa_check_auth_data(string $authData, string $rpId): array {
    if (strlen($authData) < 37) throw new RuntimeException('authData too short');
    if (!hash_equals(hash('sha256', $rpId, true), substr($authData, 0, 32))) throw new RuntimeException('rpId mismatch');
    $flags = ord($authData[32]);
    if (!($flags & 0x01)) throw new RuntimeException('user not present');
    if (!($flags & 0x04)) throw new RuntimeException('user not verified');   // Windows Hello PIN/face/fingerprint
    return [$flags, unpack('N', substr($authData, 33, 4))[1]];
}

/** Verify a registration response. Returns [credentialId (b64u), pem, alg, signCount]. */
function wa_verify_registration(array $att, string $rpId): array {
    if (($att['type'] ?? '') !== 'public-key') throw new RuntimeException('bad type');
    $resp = $att['response'] ?? [];
    wa_read_client_data($resp, 'webauthn.create', $rpId);
    $pos = 0;
    $obj = wa_cbor_decode(wa_b64u_decode((string)($resp['attestationObject'] ?? '')), $pos);
    $authData = is_array($obj) ? ($obj['authData'] ?? null) : null;
    if (!is_string($authData)) throw new RuntimeException('no authData');
    [$flags, $count] = wa_check_auth_data($authData, $rpId);
    if (!($flags & 0x40)) throw new RuntimeException('no credential data');
    if (strlen($authData) < 55) throw new RuntimeException('authData too short');
    $idLen = unpack('n', substr($authData, 53, 2))[1];
    if (strlen($authData) < 55 + $idLen || $idLen < 16) throw new RuntimeException('bad credential id');
    $credId = substr($authData, 55, $idLen);
    $p = 55 + $idLen;
    $cose = wa_cbor_decode($authData, $p);
    if (!is_array($cose)) throw new RuntimeException('bad public key');
    if (!hash_equals($credId, wa_b64u_decode((string)($att['id'] ?? '')))) throw new RuntimeException('credential id mismatch');
    [$pem, $alg] = wa_cose_to_pem($cose);
    return [wa_b64u_encode($credId), $pem, $alg, $count];
}

/** Verify a sign-in response against a stored credential row. Returns the new signature counter. */
function wa_verify_assertion(array $assertion, array $cred, string $rpId): int {
    if (($assertion['type'] ?? '') !== 'public-key') throw new RuntimeException('bad type');
    $resp = $assertion['response'] ?? [];
    [, $clientRaw] = wa_read_client_data($resp, 'webauthn.get', $rpId);
    $authData = wa_b64u_decode((string)($resp['authenticatorData'] ?? ''));
    $sig = wa_b64u_decode((string)($resp['signature'] ?? ''));
    [, $count] = wa_check_auth_data($authData, $rpId);
    $ok = openssl_verify($authData . hash('sha256', $clientRaw, true), $sig, $cred['public_key'], OPENSSL_ALGO_SHA256);
    if ($ok !== 1) throw new RuntimeException('bad signature');
    $old = (int)$cred['sign_count'];
    if (($count !== 0 || $old !== 0) && $count <= $old) throw new RuntimeException('signature counter went back (cloned key?)');
    return $count;
}
