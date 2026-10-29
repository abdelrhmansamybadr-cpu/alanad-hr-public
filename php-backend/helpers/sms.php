<?php
/**
 * Text messages (SMS) for invitations and password codes.
 *
 * Nothing is sent until a provider is configured in config/database.php:
 *     define('SMS_PROVIDER', 'twilio');            // or 'unifonic'
 *     define('SMS_DEFAULT_COUNTRY', '966');        // used when a number has no country code (966 = Saudi Arabia, 20 = Egypt)
 *     // Twilio:   TWILIO_SID, TWILIO_TOKEN, TWILIO_FROM (number or sender name)
 *     // Unifonic: UNIFONIC_APPSID, UNIFONIC_SENDER
 * For tests define HR_SMS_CAPTURE with a file path: messages are appended there instead of being sent.
 */
require_once __DIR__ . '/identity.php';

function sms_provider(): string {
    if (defined('HR_SMS_CAPTURE') && HR_SMS_CAPTURE) return 'capture';
    return defined('SMS_PROVIDER') ? strtolower((string)SMS_PROVIDER) : '';
}

function sms_configured(): bool {
    switch (sms_provider()) {
        case 'capture':  return true;
        case 'twilio':   return defined('TWILIO_SID') && defined('TWILIO_TOKEN') && defined('TWILIO_FROM') && TWILIO_SID !== '';
        case 'unifonic': return defined('UNIFONIC_APPSID') && defined('UNIFONIC_SENDER') && UNIFONIC_APPSID !== '';
        default:         return false;
    }
}

/** International digits for a number typed the local way: 0501234567 -> 966501234567. Returns null when unusable. */
function sms_number($raw): ?string {
    $raw = trim((string)$raw);
    $d = phone_digits($raw);
    if (strlen($d) < 8 || strlen($d) > 15) return null;
    if (strpos($raw, '+') === 0) return $d;
    if (strpos($d, '00') === 0) return substr($d, 2);
    $cc = defined('SMS_DEFAULT_COUNTRY') ? preg_replace('/\D/', '', (string)SMS_DEFAULT_COUNTRY) : '';
    if ($cc !== '' && strpos($d, $cc) === 0 && strlen($d) >= strlen($cc) + 8) return $d;      // already has the country code
    if (strpos($d, '0') === 0) $d = ltrim($d, '0');
    return $cc !== '' ? $cc . $d : $d;
}

/** @return array{0: bool, 1: ?string} success and, when it failed, a message that is safe to show to HR */
function sms_send($to, string $text): array {
    if (!sms_configured()) return [false, 'SMS is not set up on the server yet.'];
    $num = sms_number($to);
    if ($num === null) return [false, 'The mobile number is not valid.'];

    $provider = sms_provider();
    if ($provider === 'capture') {
        @file_put_contents(HR_SMS_CAPTURE, json_encode(['to' => $num, 'text' => $text], JSON_UNESCAPED_UNICODE) . "\n", FILE_APPEND);
        return [true, null];
    }
    if ($provider === 'twilio') {
        [$code, $body] = sms_http('https://api.twilio.com/2010-04-01/Accounts/' . rawurlencode(TWILIO_SID) . '/Messages.json',
            ['To' => '+' . $num, 'From' => TWILIO_FROM, 'Body' => $text], TWILIO_SID . ':' . TWILIO_TOKEN);
        if ($code >= 200 && $code < 300) return [true, null];
        $j = json_decode((string)$body, true);
        error_log('sms twilio: ' . $code . ' ' . substr((string)$body, 0, 300));
        return [false, 'The SMS provider refused the message' . (isset($j['message']) ? ': ' . $j['message'] : ' (' . $code . ')')];
    }
    if ($provider === 'unifonic') {
        [$code, $body] = sms_http('https://el.cloud.unifonic.com/rest/SMS/messages',
            ['AppSid' => UNIFONIC_APPSID, 'SenderID' => UNIFONIC_SENDER, 'Recipient' => $num, 'Body' => $text, 'responseType' => 'JSON']);
        $j = json_decode((string)$body, true);
        if ($code >= 200 && $code < 300 && (($j['success'] ?? '') === 'true' || ($j['success'] ?? false) === true)) return [true, null];
        error_log('sms unifonic: ' . $code . ' ' . substr((string)$body, 0, 300));
        return [false, 'The SMS provider refused the message' . (isset($j['message']) ? ': ' . $j['message'] : ' (' . $code . ')')];
    }
    return [false, 'Unknown SMS provider.'];
}

/** @return array{0:int,1:?string} HTTP status and body */
function sms_http(string $url, array $fields, ?string $basicAuth = null): array {
    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        curl_setopt_array($ch, [CURLOPT_POST => true, CURLOPT_POSTFIELDS => http_build_query($fields), CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 20, CURLOPT_CONNECTTIMEOUT => 10]);
        if ($basicAuth !== null) curl_setopt($ch, CURLOPT_USERPWD, $basicAuth);
        $body = curl_exec($ch);
        $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        return [$code, $body === false ? null : (string)$body];
    }
    $headers = "Content-Type: application/x-www-form-urlencoded\r\n" . ($basicAuth !== null ? 'Authorization: Basic ' . base64_encode($basicAuth) . "\r\n" : '');
    $ctx = stream_context_create(['http' => ['method' => 'POST', 'header' => $headers, 'content' => http_build_query($fields), 'timeout' => 20, 'ignore_errors' => true]]);
    $body = @file_get_contents($url, false, $ctx);
    $code = 0;
    foreach (($http_response_header ?? []) as $h) if (preg_match('#^HTTP/\S+\s+(\d+)#', $h, $m)) $code = (int)$m[1];
    return [$code, $body === false ? null : (string)$body];
}

/** The text of an invitation (English + Arabic in one message). */
function sms_invite_text(string $company, string $username, string $code, string $valid = '7 days'): string {
    return "$company: your username is $username and your one-time code is $code (valid $valid). Open the app, enter them and choose your password.\n"
         . "$company: اسم المستخدم $username ورمز التفعيل (يُستخدم مرة واحدة) $code. افتح التطبيق وأدخلهما ثم اختر كلمة المرور.";
}

function sms_reset_text(string $company, string $code, string $valid = '30 minutes'): string {
    return "$company: your password code is $code (valid $valid).\n$company: رمز كلمة المرور $code.";
}
