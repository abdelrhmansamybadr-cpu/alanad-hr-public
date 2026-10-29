<?php
/**
 * E-mail sending for invitations, password codes and certificates.
 *
 * Real SMTP when config/database.php defines it (recommended: a mailbox of the company, with an app password):
 *     define('SMTP_HOST', 'smtp.gmail.com'); define('SMTP_PORT', 587); define('SMTP_SECURE', 'tls');   // 'tls' (587) or 'ssl' (465)
 *     define('SMTP_USER', 'sender@example.com'); define('SMTP_PASS', 'app password');
 * Without it PHP's mail() is used, which many hosts deliver unreliably (spam folder).
 * Nothing here can break a request: failures are logged, reported as `false`, and mail_last_error() says why.
 * For tests define HR_MAIL_CAPTURE with a file path: messages are appended there instead of being sent.
 */

require_once __DIR__ . '/identity.php';

function mail_from_domain(): string {
    $host = strtolower((string)($_SERVER['HTTP_HOST'] ?? ''));
    $host = preg_replace('/:\d+$/', '', $host);
    return preg_match('/^[a-z0-9.\-]+\.[a-z]{2,}$/', $host) ? $host : 'localhost.localdomain';
}

/** One branded, bilingual (English + Arabic) message. */
function mail_template(string $company, string $titleEn, string $titleAr, string $bodyEn, string $bodyAr, ?string $code = null, ?string $linkUrl = null, ?string $linkLabel = null, array $moreLinks = []): string {
    $e = fn(string $s): string => htmlspecialchars($s, ENT_QUOTES, 'UTF-8');
    $codeHtml = $code ? '<div style="margin:18px 0;padding:14px;border-radius:12px;background:#EEF2FF;text-align:center;font-size:30px;letter-spacing:8px;font-weight:800;color:#3730A3">' . $e($code) . '</div>' : '';
    $linkHtml = $linkUrl ? '<p style="margin:16px 0"><a href="' . $e($linkUrl) . '" style="background:#00617A;color:#fff;padding:12px 20px;border-radius:10px;text-decoration:none;font-weight:700">' . $e($linkLabel ?: $linkUrl) . '</a></p>' : '';
    // further download buttons (e.g. the Windows installer next to the Android app): [[url, label], ...]
    foreach ($moreLinks as $l) {
        if (empty($l[0])) continue;
        $linkHtml .= '<p style="margin:10px 0"><a href="' . $e($l[0]) . '" style="background:#334155;color:#fff;padding:12px 20px;border-radius:10px;text-decoration:none;font-weight:700">' . $e($l[1] ?? $l[0]) . '</a></p>';
    }
    return '<!doctype html><html><body style="margin:0;background:#F4F5FA;font-family:Segoe UI,Arial,sans-serif;color:#111827">'
        . '<div style="max-width:520px;margin:0 auto;padding:24px"><div style="background:#fff;border-radius:18px;padding:26px;border:1px solid #E5E7EB">'
        . '<div style="font-size:13px;color:#6B7280;margin-bottom:6px">' . $e($company) . '</div>'
        . '<h2 style="margin:0 0 10px;font-size:20px">' . $e($titleEn) . '</h2><p style="line-height:1.6;margin:0">' . $e($bodyEn) . '</p>'
        . $codeHtml . $linkHtml
        . '<hr style="border:none;border-top:1px solid #E5E7EB;margin:20px 0">'
        . '<div dir="rtl" style="text-align:right"><h2 style="margin:0 0 10px;font-size:20px">' . $e($titleAr) . '</h2><p style="line-height:1.8;margin:0">' . $e($bodyAr) . '</p></div>'
        . '</div><p style="text-align:center;color:#9CA3AF;font-size:12px;margin-top:14px">Al Anad HR</p></div></body></html>';
}

function mail_smtp_configured(): bool {
    return defined('SMTP_HOST') && SMTP_HOST !== '' && defined('SMTP_USER') && SMTP_USER !== '' && defined('SMTP_PASS');
}

function mail_from_address(): string {
    if (mail_smtp_configured()) return defined('SMTP_FROM') && SMTP_FROM !== '' ? (string)SMTP_FROM : (string)SMTP_USER;
    return 'no-reply@' . mail_from_domain();
}

function mail_transport_name(): string {
    if (defined('HR_MAIL_CAPTURE') && HR_MAIL_CAPTURE) return 'capture';
    return mail_smtp_configured() ? 'smtp' : 'php_mail';
}

/** Why the last message could not be sent (empty when it could). */
function mail_last_error(): string { return (string)($GLOBALS['HR_MAIL_ERROR'] ?? ''); }

/** Talk SMTP to the configured server. $data is the complete message (headers, blank line, body) with CRLF line ends. */
function smtp_send(string $to, string $from, string $data): bool {
    $host = (string)SMTP_HOST;
    $port = defined('SMTP_PORT') ? (int)SMTP_PORT : 587;
    $sec  = strtolower(defined('SMTP_SECURE') ? (string)SMTP_SECURE : 'tls');
    $fp = @stream_socket_client(($sec === 'ssl' ? 'ssl://' : 'tcp://') . $host . ':' . $port, $errno, $errstr, 15, STREAM_CLIENT_CONNECT);
    if (!$fp) { $GLOBALS['HR_MAIL_ERROR'] = "Could not connect to the mail server $host:$port ($errstr)"; return false; }
    stream_set_timeout($fp, 20);
    $last = '';
    $read = function () use ($fp): string {
        $out = '';
        while (($line = fgets($fp, 515)) !== false) { $out .= $line; if (strlen($line) < 4 || $line[3] === ' ') break; }
        return $out;
    };
    $cmd = function (string $c, array $ok) use ($fp, $read, &$last): bool {
        if ($c !== '') fwrite($fp, $c . "\r\n");
        $last = $read();
        return in_array((int)substr($last, 0, 3), $ok, true);
    };
    $fail = function (string $why) use ($fp, &$last): bool {
        $GLOBALS['HR_MAIL_ERROR'] = $why . ($last ? ': ' . trim(preg_replace('/\s+/', ' ', $last)) : '');
        @fwrite($fp, "QUIT\r\n"); @fclose($fp);
        return false;
    };
    $helo = mail_from_domain();
    if (!$cmd('', [220])) return $fail('The mail server did not greet us');
    if (!$cmd("EHLO $helo", [250])) return $fail('The mail server refused EHLO');
    if ($sec === 'tls') {
        if (!$cmd('STARTTLS', [220])) return $fail('The mail server refused STARTTLS');
        if (!@stream_socket_enable_crypto($fp, true, STREAM_CRYPTO_METHOD_TLSv1_2_CLIENT | STREAM_CRYPTO_METHOD_TLSv1_3_CLIENT)) return $fail('Could not start the secure connection');
        if (!$cmd("EHLO $helo", [250])) return $fail('The mail server refused EHLO after STARTTLS');
    }
    if (!$cmd('AUTH LOGIN', [334])) return $fail('The mail server does not accept this sign-in method');
    if (!$cmd(base64_encode((string)SMTP_USER), [334])) return $fail('The mail server refused the user name');
    if (!$cmd(base64_encode((string)SMTP_PASS), [235])) return $fail('The mail server refused the password (for Gmail use an App Password)');
    if (!$cmd("MAIL FROM:<$from>", [250])) return $fail('The sender address was refused');
    if (!$cmd("RCPT TO:<$to>", [250, 251])) return $fail('The recipient address was refused');
    if (!$cmd('DATA', [354])) return $fail('The mail server refused the message');
    $data = preg_replace('/^\./m', '..', $data);
    fwrite($fp, $data . "\r\n.\r\n");
    $last = $read();
    if ((int)substr($last, 0, 3) !== 250) return $fail('The mail server did not accept the message');
    @fwrite($fp, "QUIT\r\n"); @fclose($fp);
    return true;
}

/** Deliver one finished message ($headers are 'Name: value' lines, $body already encoded). */
function mail_deliver(string $to, string $subject, array $headers, string $body, string $fromName): bool {
    $GLOBALS['HR_MAIL_ERROR'] = '';
    $from = mail_from_address();
    $encSubject = '=?UTF-8?B?' . base64_encode($subject) . '?=';
    $fromHeader = 'From: =?UTF-8?B?' . base64_encode($fromName) . "?= <$from>";
    try {
        if (mail_smtp_configured()) {
            $all = array_merge(['Date: ' . date('r'), 'Message-ID: <' . bin2hex(random_bytes(10)) . '@' . mail_from_domain() . '>', "To: <$to>", 'Subject: ' . $encSubject, $fromHeader, 'Reply-To: ' . $from], $headers);
            $ok = smtp_send($to, $from, implode("\r\n", $all) . "\r\n\r\n" . $body);
            if (!$ok) error_log('smtp_send: ' . mail_last_error());
            return $ok;
        }
        $ok = @mail($to, $encSubject, $body, implode("\r\n", array_merge([$fromHeader, 'Reply-To: ' . $from], $headers)), '-f' . $from);
        if (!$ok) { $GLOBALS['HR_MAIL_ERROR'] = 'The server did not accept the message (PHP mail). Set up SMTP for reliable delivery.'; error_log('mail_deliver: php mail failed'); }
        return (bool)$ok;
    } catch (Throwable $e) {
        $GLOBALS['HR_MAIL_ERROR'] = $e->getMessage();
        error_log('mail_deliver: ' . $e->getMessage());
        return false;
    }
}

function mail_send(string $to, string $subject, string $html, string $fromName = 'Al Anad HR'): bool {
    $to = trim($to);
    if (!email_is_real($to) || preg_match('/[\r\n]/', $to . $subject . $fromName)) { $GLOBALS['HR_MAIL_ERROR'] = 'The e-mail address is not valid.'; return false; }
    if (defined('HR_MAIL_CAPTURE') && HR_MAIL_CAPTURE) {       // tests / local development
        $GLOBALS['HR_MAIL_ERROR'] = '';
        @file_put_contents(HR_MAIL_CAPTURE, json_encode(['to' => $to, 'subject' => $subject, 'html' => $html], JSON_UNESCAPED_UNICODE) . "\n", FILE_APPEND);
        return true;
    }
    return mail_deliver($to, $subject, ['MIME-Version: 1.0', 'Content-Type: text/html; charset=UTF-8', 'Content-Transfer-Encoding: base64', 'X-Mailer: Al Anad HR'], chunk_split(base64_encode($html)), $fromName);
}

/** https://<this host>, always https for a real domain (the proxy in front may hide that the request was secure). */
function mail_site_url(): string {
    $host = mail_from_domain();
    $local = $host === 'localhost.localdomain' || preg_match('/^(localhost|127\.|10\.|192\.168\.)/', $host);
    return ($local && !(isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'http://' : 'https://') . $host;
}

/**
 * Where the people download the app: 'android' = the latest APK, 'windows' = the installer named in windows.json
 * (read from this server, so the e-mail always points at the current release). Null when there is nothing to link to.
 */
function mail_app_url(string $platform): ?string {
    $site = mail_site_url();
    if ($platform === 'android') return "$site/app/alanad/AlAnad-HR.apk";
    $f = dirname(__DIR__) . '/app/alanad/windows.json';
    $j = is_file($f) ? json_decode((string)@file_get_contents($f), true) : null;
    $u = is_array($j) ? (string)($j['installerUrl'] ?? '') : '';
    if ($u === '' || !preg_match('~/(app/[A-Za-z0-9_./-]+\.exe)$~', $u, $m)) return null;
    return "$site/" . $m[1];                      // same host as the e-mail, whatever host the manifest was written for
}

/**
 * Send an invitation (new account) or a reset code. $username is what the person types to sign in (their e-mail
 * address or mobile number). Returns whether the server accepted the mail.
 */
function mail_send_code(string $to, string $company, string $purpose, string $code, string $valid, ?string $username = null): bool {
    $invite = $purpose === 'activate';
    $site = mail_site_url();
    $user = $username !== null && $username !== '' ? $username : $to;
    $subject = $invite ? "$company: your Al Anad HR account" : "$company: your Al Anad HR password code";
    $enBody = $invite
        ? "$company has created your account. Username: $user. Company: $company. Your verification code is below; it works once and is valid for $valid. Open the Al Anad HR app (or the website), choose \"Continue\", enter your username and the code, then choose your password."
        : "Open the Al Anad HR app, choose \"Forgot password\" and enter this code with your new password. It is valid for $valid.";
    $arBody = $invite
        ? "أنشأت لك $company حسابًا. اسم المستخدم: $user. الشركة: $company. رمز التحقق أدناه يُستخدم مرة واحدة فقط وصالح لمدة محدودة. افتح تطبيق Al Anad HR (أو الموقع) واختر \"المتابعة\" ثم أدخل اسم المستخدم والرمز واختر كلمة المرور."
        : 'افتح تطبيق Al Anad HR واختر "نسيت كلمة المرور" ثم أدخل هذا الرمز مع كلمة المرور الجديدة. الرمز صالح لمدة محدودة.';
    $html = mail_template(
        $company,
        $invite ? 'Your account is ready' : 'Your password reset code',
        $invite ? 'حسابك جاهز' : 'رمز إعادة تعيين كلمة المرور',
        $enBody,
        $arBody,
        $code,
        $invite ? mail_app_url('android') : null,
        $invite ? 'Download the app (Android) / تحميل التطبيق (أندرويد)' : null,
        $invite ? [[mail_app_url('windows'), 'Download for Windows / تحميل نسخة ويندوز']] : []
    );
    return mail_send($to, $subject, $html, $company);
}

/**
 * Same as mail_send() with file attachments: $attachments = [['name' => 'a.pdf', 'mime' => 'application/pdf', 'data' => <bytes>], ...].
 * In capture mode (tests) the attachment names and sizes are recorded instead of the bytes.
 */
function mail_send_attach(string $to, string $subject, string $html, array $attachments, string $fromName = 'Al Anad HR'): bool {
    $to = trim($to);
    if (!email_is_real($to) || preg_match('/[\r\n]/', $to . $subject . $fromName)) { $GLOBALS['HR_MAIL_ERROR'] = 'The e-mail address is not valid.'; return false; }
    if (defined('HR_MAIL_CAPTURE') && HR_MAIL_CAPTURE) {
        $GLOBALS['HR_MAIL_ERROR'] = '';
        $meta = array_map(fn($a) => ['name' => $a['name'], 'mime' => $a['mime'], 'bytes' => strlen($a['data'])], $attachments);
        @file_put_contents(HR_MAIL_CAPTURE, json_encode(['to' => $to, 'subject' => $subject, 'html' => $html, 'attachments' => $meta], JSON_UNESCAPED_UNICODE) . "\n", FILE_APPEND);
        return true;
    }
    $boundary = 'b' . bin2hex(random_bytes(12));
    $msg  = "--$boundary\r\nContent-Type: text/html; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n" . chunk_split(base64_encode($html)) . "\r\n";
    foreach ($attachments as $a) {
        $name = preg_replace('/[^A-Za-z0-9._-]/', '_', $a['name']);
        $msg .= "--$boundary\r\nContent-Type: {$a['mime']}; name=\"$name\"\r\nContent-Transfer-Encoding: base64\r\nContent-Disposition: attachment; filename=\"$name\"\r\n\r\n"
              . chunk_split(base64_encode($a['data'])) . "\r\n";
    }
    $msg .= "--$boundary--";
    return mail_deliver($to, $subject, ['MIME-Version: 1.0', 'Content-Type: multipart/mixed; boundary="' . $boundary . '"', 'X-Mailer: Al Anad HR'], $msg, $fromName);
}
