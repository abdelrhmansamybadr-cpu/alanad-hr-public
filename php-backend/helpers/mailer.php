<?php
/**
 * Plain e-mail sending for invites and password resets.
 *
 * Uses PHP's mail(), which works on typical shared hosting without any extra setup. Nothing here can break a
 * request: failures are logged and reported as `false`. For tests (and local development) define HR_MAIL_CAPTURE
 * in config/database.php with a file path and messages are appended to that file instead of being sent.
 */

function mail_from_domain(): string {
    $host = strtolower((string)($_SERVER['HTTP_HOST'] ?? ''));
    $host = preg_replace('/:\d+$/', '', $host);
    return preg_match('/^[a-z0-9.\-]+\.[a-z]{2,}$/', $host) ? $host : 'localhost.localdomain';
}

/** One branded, bilingual (English + Arabic) message. */
function mail_template(string $company, string $titleEn, string $titleAr, string $bodyEn, string $bodyAr, ?string $code = null, ?string $linkUrl = null, ?string $linkLabel = null): string {
    $e = fn(string $s): string => htmlspecialchars($s, ENT_QUOTES, 'UTF-8');
    $codeHtml = $code ? '<div style="margin:18px 0;padding:14px;border-radius:12px;background:#EEF2FF;text-align:center;font-size:30px;letter-spacing:8px;font-weight:800;color:#3730A3">' . $e($code) . '</div>' : '';
    $linkHtml = $linkUrl ? '<p style="margin:16px 0"><a href="' . $e($linkUrl) . '" style="background:#00617A;color:#fff;padding:12px 20px;border-radius:10px;text-decoration:none;font-weight:700">' . $e($linkLabel ?: $linkUrl) . '</a></p>' : '';
    return '<!doctype html><html><body style="margin:0;background:#F4F5FA;font-family:Segoe UI,Arial,sans-serif;color:#111827">'
        . '<div style="max-width:520px;margin:0 auto;padding:24px"><div style="background:#fff;border-radius:18px;padding:26px;border:1px solid #E5E7EB">'
        . '<div style="font-size:13px;color:#6B7280;margin-bottom:6px">' . $e($company) . '</div>'
        . '<h2 style="margin:0 0 10px;font-size:20px">' . $e($titleEn) . '</h2><p style="line-height:1.6;margin:0">' . $e($bodyEn) . '</p>'
        . $codeHtml . $linkHtml
        . '<hr style="border:none;border-top:1px solid #E5E7EB;margin:20px 0">'
        . '<div dir="rtl" style="text-align:right"><h2 style="margin:0 0 10px;font-size:20px">' . $e($titleAr) . '</h2><p style="line-height:1.8;margin:0">' . $e($bodyAr) . '</p></div>'
        . '</div><p style="text-align:center;color:#9CA3AF;font-size:12px;margin-top:14px">Al Anad HR</p></div></body></html>';
}

function mail_send(string $to, string $subject, string $html, string $fromName = 'Al Anad HR'): bool {
    $to = trim($to);
    if (!filter_var($to, FILTER_VALIDATE_EMAIL) || preg_match('/[\r\n]/', $to . $subject . $fromName)) return false;

    if (defined('HR_MAIL_CAPTURE') && HR_MAIL_CAPTURE) {       // tests / local development
        @file_put_contents(HR_MAIL_CAPTURE, json_encode(['to' => $to, 'subject' => $subject, 'html' => $html], JSON_UNESCAPED_UNICODE) . "\n", FILE_APPEND);
        return true;
    }
    $from = 'no-reply@' . mail_from_domain();
    $headers = [
        'MIME-Version: 1.0',
        'Content-Type: text/html; charset=UTF-8',
        'From: =?UTF-8?B?' . base64_encode($fromName) . "?= <$from>",
        'Reply-To: ' . $from,
        'X-Mailer: Al Anad HR',
    ];
    $ok = false;
    try {
        $ok = @mail($to, '=?UTF-8?B?' . base64_encode($subject) . '?=', $html, implode("\r\n", $headers), '-f' . $from);
    } catch (Throwable $e) {
        error_log('mail_send: ' . $e->getMessage());
    }
    if (!$ok) error_log('mail_send: the server did not accept the message for ' . preg_replace('/(^.).*(@.*$)/', '$1***$2', $to));
    return (bool)$ok;
}

/** Send an invite (new account) or reset code to an employee. Returns whether the server accepted the mail. */
function mail_send_code(string $to, string $company, string $purpose, string $code, string $valid): bool {
    $invite = $purpose === 'activate';
    $site = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off' ? 'https://' : 'http://') . mail_from_domain();
    $subject = $invite ? "$company: your Al Anad HR invitation" : "$company: your Al Anad HR password code";
    $html = mail_template(
        $company,
        $invite ? 'You are invited to Al Anad HR' : 'Your password reset code',
        $invite ? 'دعوة للانضمام إلى Al Anad HR' : 'رمز إعادة تعيين كلمة المرور',
        $invite ? "Install the Al Anad HR app, choose \"Continue with email\", enter this email address and the code below. It is valid for $valid."
                : "Open the Al Anad HR app, choose \"Forgot password\" and enter this code with your new password. It is valid for $valid.",
        $invite ? 'ثبّت تطبيق Al Anad HR واختر "المتابعة بالبريد الإلكتروني" ثم أدخل بريدك والرمز التالي. الرمز صالح لمدة محدودة.'
                : 'افتح تطبيق Al Anad HR واختر "نسيت كلمة المرور" ثم أدخل هذا الرمز مع كلمة المرور الجديدة. الرمز صالح لمدة محدودة.',
        $code,
        $invite ? "$site/app/HR-Mobile-App.apk" : null,
        $invite ? 'Download the app' : null
    );
    return mail_send($to, $subject, $html, $company);
}
