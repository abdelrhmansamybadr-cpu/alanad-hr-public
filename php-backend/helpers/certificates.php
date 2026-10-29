<?php
/**
 * Leaving certificates: image handling, a tiny PDF writer, serial numbers, starter designs and the
 * scheduled closing of an employee's account.
 *
 * The certificate itself is drawn by the app (web canvas / Flutter canvas) so Arabic is shaped correctly;
 * the server only stores the finished picture, wraps it in a PDF and e-mails both.
 */

const CERT_MAX_IMAGE_BYTES = 8 * 1024 * 1024;

/** Absolute folder for this company's certificate files (created on first use, closed to the web). */
function cert_dir(): string {
    $root = __DIR__ . '/../uploads/certificates';
    if (!is_dir($root)) @mkdir($root, 0755, true);
    if (!is_file($root . '/.htaccess')) @file_put_contents($root . '/.htaccess', "Require all denied\n");
    $dir = $root . '/' . cid();
    if (!is_dir($dir)) @mkdir($dir, 0755, true);
    return $dir;
}

/** Decode "data:image/png;base64,...": returns [bytes, mime, width, height] or null when it is not a usable picture. */
function cert_decode_image($dataUrl): ?array {
    if (!is_string($dataUrl) || !preg_match('#^data:image/(png|jpe?g|webp);base64,([A-Za-z0-9+/=\s]+)$#', $dataUrl, $m)) return null;
    $bytes = base64_decode(preg_replace('/\s+/', '', $m[2]), true);
    if ($bytes === false || $bytes === '' || strlen($bytes) > CERT_MAX_IMAGE_BYTES) return null;
    $mime = (new finfo(FILEINFO_MIME_TYPE))->buffer($bytes);          // trust the content, not the label
    if (!in_array($mime, ['image/png', 'image/jpeg', 'image/webp'], true)) return null;
    $info = @getimagesizefromstring($bytes);
    if (!$info || $info[0] < 16 || $info[1] < 16 || $info[0] > 8000 || $info[1] > 8000) return null;
    return [$bytes, $mime, (int)$info[0], (int)$info[1]];
}

/** Re-encode any accepted picture as JPEG on a white page (PDF pages embed JPEG directly). */
function cert_to_jpeg(string $bytes, string $mime): ?string {
    if ($mime === 'image/jpeg') return $bytes;
    if (!function_exists('imagecreatefromstring')) return null;
    $src = @imagecreatefromstring($bytes);
    if (!$src) return null;
    $w = imagesx($src); $h = imagesy($src);
    $dst = imagecreatetruecolor($w, $h);
    imagefill($dst, 0, 0, imagecolorallocate($dst, 255, 255, 255));
    imagecopy($dst, $src, 0, 0, 0, 0, $w, $h);
    ob_start();
    imagejpeg($dst, null, 92);
    $out = ob_get_clean();
    imagedestroy($src); imagedestroy($dst);
    return $out ?: null;
}

/** Save bytes under uploads/certificates/<company>/ and return the path relative to the backend root. */
function cert_store(string $bytes, string $ext): string {
    $dir = cert_dir();
    $name = bin2hex(random_bytes(16)) . '.' . $ext;
    if (file_put_contents($dir . '/' . $name, $bytes) === false) error_response('Could not save the file', 500);
    return 'uploads/certificates/' . cid() . '/' . $name;
}

/** Send a stored file (only from inside uploads/certificates) and stop. */
function cert_stream(string $relPath, string $mime, string $downloadName, bool $attachment = false): void {
    $full = realpath(__DIR__ . '/../' . $relPath);
    $root = realpath(__DIR__ . '/../uploads/certificates');
    if (!$full || !$root || strpos($full, $root) !== 0 || !is_file($full)) error_response('File not found', 404);
    header('Content-Type: ' . $mime);
    header('Content-Length: ' . filesize($full));
    header('Content-Disposition: ' . ($attachment ? 'attachment' : 'inline') . '; filename="' . preg_replace('/[^A-Za-z0-9._-]/', '_', $downloadName) . '"');
    header('X-Content-Type-Options: nosniff');
    header('Cache-Control: private, max-age=0');
    readfile($full);
    exit;
}

/** A one-page PDF that shows the JPEG over the whole page. $ptW/$ptH is the page size in points. */
function cert_pdf(string $jpeg, int $pxW, int $pxH, float $ptW, float $ptH): string {
    $objs = [];
    $objs[1] = '<< /Type /Catalog /Pages 2 0 R >>';
    $objs[2] = '<< /Type /Pages /Kids [3 0 R] /Count 1 >>';
    $objs[3] = sprintf('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %.2F %.2F] /Contents 4 0 R /Resources << /XObject << /Im0 5 0 R >> >> >>', $ptW, $ptH);
    $content = sprintf("q %.2F 0 0 %.2F 0 0 cm /Im0 Do Q", $ptW, $ptH);
    $objs[4] = "<< /Length " . strlen($content) . " >>\nstream\n$content\nendstream";
    $objs[5] = "<< /Type /XObject /Subtype /Image /Width $pxW /Height $pxH /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length " . strlen($jpeg) . " >>\nstream\n" . $jpeg . "\nendstream";

    $pdf = "%PDF-1.4\n";
    $offsets = [];
    foreach ($objs as $n => $body) {
        $offsets[$n] = strlen($pdf);
        $pdf .= "$n 0 obj\n$body\nendobj\n";
    }
    $xref = strlen($pdf);
    $pdf .= "xref\n0 " . (count($objs) + 1) . "\n0000000000 65535 f \n";
    foreach ($offsets as $o) $pdf .= sprintf("%010d 00000 n \n", $o);
    $pdf .= "trailer\n<< /Size " . (count($objs) + 1) . " /Root 1 0 R >>\nstartxref\n$xref\n%%EOF";
    return $pdf;
}

/** Reserve the next serial number of the year, e.g. CERT-2026-0007, by inserting the draft row (unique per company). */
function cert_create_draft(PDO $pdo, int $employeeId, ?int $templateId, string $kind, int $year): array {
    for ($try = 0; $try < 5; $try++) {
        $s = $pdo->prepare("SELECT MAX(CAST(SUBSTRING_INDEX(serial, '-', -1) AS UNSIGNED)) FROM certificates WHERE company_id = ? AND serial LIKE ?");
        $s->execute([cid(), "CERT-$year-%"]);
        $serial = sprintf('CERT-%d-%04d', $year, (int)$s->fetchColumn() + 1 + $try);
        try {
            $pdo->prepare("INSERT INTO certificates (company_id, employee_id, template_id, serial, kind, status) VALUES (?, ?, ?, ?, ?, 'draft')")
                ->execute([cid(), $employeeId, $templateId, $serial, $kind]);
            return ['id' => (int)$pdo->lastInsertId(), 'serial' => $serial];
        } catch (PDOException $e) {
            if ($e->getCode() !== '23000') throw $e;       // duplicate serial: somebody else took it, try the next
        }
    }
    error_response('Could not reserve a certificate number, please try again', 503);
}

/** Drafts nobody finished are removed after a day (never touches issued certificates). */
function cert_cleanup_drafts(PDO $pdo): void {
    $pdo->prepare("DELETE FROM certificates WHERE company_id = ? AND status = 'draft' AND created_at < (NOW() - INTERVAL 1 DAY)")->execute([cid()]);
}

// ------------------------------------------------------------------ scheduled account closing

/** When should the account close? $plan = {mode: none|now|in|date, days?, date?}. Returns [DateTime|null, label]. */
function exit_close_time(PDO $pdo, array $plan): array {
    $mode = (string)($plan['mode'] ?? 'none');
    $now  = att_now($pdo);
    if ($mode === 'now') return [$now, 'now'];
    if ($mode === 'in') {
        $days = max(1, min(365, (int)($plan['days'] ?? 0)));
        return [(clone $now)->modify("+$days days"), "in $days days"];
    }
    if ($mode === 'date') {
        $d = DateTime::createFromFormat('Y-m-d', (string)($plan['date'] ?? ''));
        if (!$d || $d->format('Y-m-d') !== (string)$plan['date']) error_response('Closing date must be YYYY-MM-DD', 422);
        $d->setTime(23, 59, 59);
        return [$d, 'on ' . $d->format('Y-m-d')];
    }
    return [null, 'none'];
}

/** Plan (or replace) the closing of an employee's account. Mode "now" closes it immediately. Returns the closure row or null. */
function exit_schedule(PDO $pdo, int $employeeId, ?int $certificateId, array $plan, ?string $leaveDate, string $reason): ?array {
    [$when, $label] = exit_close_time($pdo, $plan);
    $pdo->prepare("UPDATE exit_closures SET status = 'cancelled' WHERE company_id = ? AND employee_id = ? AND status = 'pending'")->execute([cid(), $employeeId]);
    if ($when === null) return null;
    $pdo->prepare("INSERT INTO exit_closures (company_id, employee_id, certificate_id, close_at, status, leave_date, reason, set_by) VALUES (?, ?, ?, ?, 'pending', ?, ?, ?)")
        ->execute([cid(), $employeeId, $certificateId, $when->format('Y-m-d H:i:s'), $leaveDate, mb_substr($reason, 0, 255), (int)me()['id']]);
    $id = (int)$pdo->lastInsertId();
    if ($label === 'now') exit_apply_due($pdo);
    $s = $pdo->prepare("SELECT * FROM exit_closures WHERE id = ?");
    $s->execute([$id]);
    return $s->fetch() ?: null;
}

/** Close every account whose time has come (called whenever the app asks for its notifications and on sign-in). */
function exit_apply_due(PDO $pdo): void {
    try {
        $now = att_now($pdo)->format('Y-m-d H:i:s');
        $s = $pdo->prepare("SELECT * FROM exit_closures WHERE company_id = ? AND status = 'pending' AND close_at <= ? ORDER BY id LIMIT 25");
        $s->execute([cid(), $now]);
        $rows = $s->fetchAll();
        if (!$rows) return;
        require_once __DIR__ . '/../api/employees.php';
        foreach ($rows as $r) {
            $claim = $pdo->prepare("UPDATE exit_closures SET status = 'done', done_at = ? WHERE id = ? AND status = 'pending'");
            $claim->execute([$now, $r['id']]);
            if ($claim->rowCount() !== 1) continue;                    // another request already took it
            $e = $pdo->prepare("SELECT first_name, last_name, status FROM employees WHERE id = ? AND company_id = ?");
            $e->execute([$r['employee_id'], cid()]);
            $emp = $e->fetch();
            if (!$emp) continue;
            if ($emp['status'] !== 'inactive') {
                employees_do_terminate((int)$r['employee_id'], $r['leave_date'] ?: null, $r['reason'] ?: 'Left the company', $pdo);
            }
            notify_hr($pdo, 'account_closed', 'Account closed', "{$emp['first_name']} {$emp['last_name']}'s account was closed as planned.", ['employee_id' => (int)$r['employee_id']]);
        }
    } catch (Throwable $e) {
        error_log('exit_apply_due: ' . $e->getMessage());      // never break the request that triggered it
    }
}

// ------------------------------------------------------------------ starter designs

function cert_block(string $id, string $text, float $x, float $y, float $w, float $size, array $o = []): array {
    return array_merge(['id' => $id, 'type' => 'text', 'text' => $text, 'x' => $x, 'y' => $y, 'w' => $w, 'size' => $size,
        'color' => '#1f2937', 'align' => 'center', 'bold' => false, 'italic' => false, 'font' => 'sans', 'lh' => 1.5], $o);
}

/** Ready-made designs the HR team can start from (the layout is the same JSON the designer saves). */
function cert_samples(): array {
    $frame = ['style' => 'double', 'color' => '#b8975a', 'width' => 7, 'inset' => 26];
    $gold = '#8a6d2f';
    $en = fn(string $kind, string $title, string $intro, string $body, string $name) => [
        'name' => $name, 'kind' => $kind, 'lang' => 'en', 'width' => 1123, 'height' => 794, 'bgColor' => '#fffdf8',
        'layout' => ['frame' => $frame, 'blocks' => [
            cert_block('title', $title, 10, 13, 80, 6.2, ['bold' => true, 'font' => 'serif', 'color' => $gold]),
            cert_block('company', '{company}', 10, 24, 80, 3.4, ['color' => '#374151']),
            cert_block('intro', $intro, 10, 34, 80, 3.1, ['color' => '#4b5563', 'italic' => true]),
            cert_block('name', '{name}', 10, 40, 80, 7, ['bold' => true, 'font' => 'serif', 'color' => '#111827']),
            cert_block('body', $body, 12, 54, 76, 3.2, ['lh' => 1.7]),
            cert_block('meta', "Date of issue: {issue_date}\nCertificate No: {serial}", 8, 84, 34, 2.5, ['align' => 'left', 'color' => '#6b7280']),
            cert_block('sign', "____________________\nHuman Resources Manager", 62, 82, 30, 2.8, ['color' => '#374151']),
        ]],
    ];
    $ar = fn(string $kind, string $title, string $intro, string $body, string $name) => [
        'name' => $name, 'kind' => $kind, 'lang' => 'ar', 'width' => 1123, 'height' => 794, 'bgColor' => '#fffdf8',
        'layout' => ['frame' => $frame, 'blocks' => [
            cert_block('title', $title, 10, 13, 80, 6.4, ['bold' => true, 'font' => 'serif', 'color' => $gold]),
            cert_block('company', '{company}', 10, 24, 80, 3.6, ['color' => '#374151']),
            cert_block('intro', $intro, 10, 34, 80, 3.3, ['color' => '#4b5563']),
            cert_block('name', '{name}', 10, 40, 80, 7, ['bold' => true, 'font' => 'serif', 'color' => '#111827']),
            cert_block('body', $body, 12, 54, 76, 3.4, ['lh' => 1.8]),
            cert_block('meta', "تاريخ الإصدار: {issue_date}\nرقم الشهادة: {serial}", 58, 84, 34, 2.6, ['align' => 'right', 'color' => '#6b7280']),
            cert_block('sign', "____________________\nمدير الموارد البشرية", 8, 82, 30, 2.9, ['color' => '#374151']),
        ]],
    ];
    return [
        $en('experience', 'CERTIFICATE OF EXPERIENCE', 'This is to certify that', 'worked with {company} as {position} in the {department} department from {start_date} to {end_date} ({duration}). During this period the employee showed dedication and professionalism. We wish them every success in the future.', 'Experience certificate (English)'),
        $ar('experience', 'شهادة خبرة', 'تشهد {company} بأن السيد/ة', 'قد عمل/ت لدينا بوظيفة {position} في قسم {department} خلال الفترة من {start_date} إلى {end_date} ({duration})، وكان/ت خلالها مثالًا في الالتزام والكفاءة. نتمنى له/ا التوفيق في مسيرته/ا المهنية.', 'شهادة خبرة (عربي)'),
        $en('end_of_service', 'END OF SERVICE CERTIFICATE', 'This certifies that', 'was employed by {company} as {position} in the {department} department from {start_date} until {end_date} ({duration}), and has left the company on completion of the employment relationship. All dues have been settled in line with the company policy.', 'End of service (English)'),
        $ar('end_of_service', 'شهادة إنهاء خدمة', 'تفيد {company} بأن السيد/ة', 'كان/ت يعمل/ت لدينا بوظيفة {position} في قسم {department} من تاريخ {start_date} حتى تاريخ {end_date} ({duration})، وقد انتهت علاقته/ا الوظيفية بالشركة في هذا التاريخ.', 'إنهاء خدمة (عربي)'),
    ];
}
