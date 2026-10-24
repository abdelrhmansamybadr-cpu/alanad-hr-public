<?php
/**
 * Documents API handler (company-scoped)
 *
 *   GET    /documents/types                          document types (everyone)
 *   POST/PUT/DELETE /documents/types[/id]            manage types (HR)
 *   GET    /documents/employee/:id                   list an employee's documents (HR or that employee)
 *   POST   /documents/employee/:id/upload/:typeId    upload (HR or that employee), multipart field "file"
 *   DELETE /documents/employee/:id/document/:docId   delete (HR or that employee)
 *   GET    /documents/file/:docId                    download / view a file (HR or its owner)
 *
 * Files live in uploads/employees/ which the web server refuses to serve directly;
 * they are only ever streamed through /documents/file/:docId after an access check.
 */
function handle_documents(string $path, string $method, array $body): void {
    $pdo      = getDB();
    $segments = explode('/', $path);
    $sub  = $segments[1] ?? '';
    $sub2 = $segments[2] ?? '';

    if ($sub === 'types') {
        $typeId = ($sub2 !== '' && is_numeric($sub2)) ? intval($sub2) : null;
        handle_document_types($typeId, $method, $body, $pdo);
        return;
    }

    if ($sub === 'file' && $sub2 !== '' && is_numeric($sub2)) {
        if ($method !== 'GET') error_response('Method not allowed', 405);
        documents_stream(intval($sub2), $pdo);
        return;
    }

    if ($sub === 'employee') {
        $empId = (isset($segments[2]) && is_numeric($segments[2])) ? intval($segments[2]) : null;
        if ($empId === null) error_response('Invalid path', 404);
        documents_assert_access($pdo, $empId);

        $action = $segments[3] ?? '';
        $extra  = (isset($segments[4]) && is_numeric($segments[4])) ? intval($segments[4]) : null;
        if ($action === 'upload' && $extra !== null) {
            if ($method !== 'POST') error_response('Method not allowed', 405);
            documents_upload($empId, $extra, $pdo);
        } elseif ($action === 'document' && $extra !== null) {
            if ($method !== 'DELETE') error_response('Method not allowed', 405);
            documents_delete($empId, $extra, $pdo);
        } elseif ($action === '') {
            if ($method !== 'GET') error_response('Method not allowed', 405);
            documents_list($empId, $pdo);
        }
        error_response('Invalid path', 404);
    }

    error_response('Invalid path', 404);
}

/** HR may act on any employee of the company; an employee only on themselves. */
function documents_assert_access(PDO $pdo, int $employeeId): void {
    if (!employee_in_company($pdo, $employeeId)) error_response('Employee not found', 404);
    if (!is_hr() && $employeeId !== own_employee_id()) error_response('Forbidden. Insufficient permissions.', 403);
}

// ---- Document Types ----

function handle_document_types(?int $typeId, string $method, array $body, PDO $pdo): void {
    if ($typeId !== null) {
        switch ($method) {
            case 'PUT':    require_hr(); doc_types_update($typeId, $body, $pdo); break;
            case 'DELETE': require_hr(); doc_types_delete($typeId, $pdo); break;
            default:       error_response('Method not allowed', 405);
        }
    } else {
        switch ($method) {
            case 'GET':  doc_types_list($pdo); break;
            case 'POST': require_hr(); doc_types_create($body, $pdo); break;
            default:     error_response('Method not allowed', 405);
        }
    }
}

function doc_types_fetch(PDO $pdo, int $id): ?array {
    $row = $pdo->prepare("SELECT *, label AS name FROM required_document_types WHERE id = ? AND company_id = ?");
    $row->execute([$id, cid()]);
    return $row->fetch() ?: null;
}

function doc_types_list(PDO $pdo): void {
    $stmt = $pdo->prepare("SELECT *, label AS name FROM required_document_types WHERE company_id = ? ORDER BY order_num, id");
    $stmt->execute([cid()]);
    json_response(['success' => true, 'data' => $stmt->fetchAll()]);
}

function doc_types_create(array $body, PDO $pdo): void {
    $label = trim($body['label'] ?? $body['name'] ?? '');
    if ($label === '') {
        error_response('Label is required');
    }
    $pdo->prepare("INSERT INTO required_document_types (company_id, label, order_num, created_at) VALUES (?, ?, ?, NOW())")
        ->execute([cid(), $label, isset($body['order_num']) ? intval($body['order_num']) : 0]);

    json_response(['success' => true, 'data' => doc_types_fetch($pdo, (int)$pdo->lastInsertId())], 201);
}

function doc_types_update(int $id, array $body, PDO $pdo): void {
    if (!doc_types_fetch($pdo, $id)) {
        error_response('Document type not found', 404);
    }
    $fields = [];
    $params = [];
    if (array_key_exists('label', $body) || array_key_exists('name', $body)) {
        $fields[] = 'label = ?';
        $params[]  = trim((string)($body['label'] ?? $body['name']));
    }
    if (array_key_exists('order_num', $body)) {
        $fields[] = 'order_num = ?';
        $params[]  = intval($body['order_num']);
    }
    if (empty($fields)) {
        error_response('No fields to update');
    }
    $params[] = $id;
    $params[] = cid();
    $pdo->prepare("UPDATE required_document_types SET " . implode(', ', $fields) . " WHERE id = ? AND company_id = ?")->execute($params);
    json_response(['success' => true, 'data' => doc_types_fetch($pdo, $id)]);
}

function doc_types_delete(int $id, PDO $pdo): void {
    if (!doc_types_fetch($pdo, $id)) {
        error_response('Document type not found', 404);
    }
    $pdo->prepare("DELETE FROM required_document_types WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
    json_response(['success' => true, 'message' => 'Document type deleted']);
}

// ---- Employee Documents ----

function documents_row_sql(): string {
    return "SELECT ed.*, rdt.label AS type_label, rdt.label AS type_name, ed.document_type_id AS type_id,
                   CONCAT('/api/documents/file/', ed.id) AS download_url
            FROM employee_documents ed
            JOIN required_document_types rdt ON rdt.id = ed.document_type_id";
}

function documents_list(int $employeeId, PDO $pdo): void {
    $stmt = $pdo->prepare(documents_row_sql() . " WHERE ed.employee_id = ? AND ed.company_id = ? ORDER BY rdt.order_num, ed.uploaded_at DESC");
    $stmt->execute([$employeeId, cid()]);
    json_response(['success' => true, 'data' => $stmt->fetchAll()]);
}

function documents_upload(int $employeeId, int $typeId, PDO $pdo): void {
    if (!doc_types_fetch($pdo, $typeId)) {
        error_response('Document type not found', 404);
    }
    if (!isset($_FILES['file']) || $_FILES['file']['error'] !== UPLOAD_ERR_OK) {
        error_response('File upload error: ' . ($_FILES['file']['error'] ?? 'No file uploaded'));
    }

    $file = $_FILES['file'];
    if ($file['size'] > 10 * 1024 * 1024) {
        error_response('File size must not exceed 10MB');
    }

    // Trust the file content, not the client-declared type
    $mimeType = (new finfo(FILEINFO_MIME_TYPE))->file($file['tmp_name']) ?: 'application/octet-stream';
    $allowed  = [
        'image/jpeg' => 'jpg', 'image/png' => 'png', 'image/webp' => 'webp',
        'application/pdf' => 'pdf', 'text/plain' => 'txt',
        'application/msword' => 'doc',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document' => 'docx',
    ];
    if (!isset($allowed[$mimeType])) {
        error_response('File type not allowed. Accepted: images, PDF, DOC, DOCX, TXT');
    }

    $fileName  = mb_substr(preg_replace('/[^\p{L}\p{N}\.\-_ ]/u', '_', basename($file['name'])), 0, 200);
    $uploadDir = __DIR__ . '/../uploads/employees/' . cid() . '/' . $employeeId . '/';
    if (!is_dir($uploadDir)) {
        mkdir($uploadDir, 0755, true);
    }
    $uniqueName = bin2hex(random_bytes(16)) . '.' . $allowed[$mimeType];
    if (!move_uploaded_file($file['tmp_name'], $uploadDir . $uniqueName)) {
        error_response('Failed to save uploaded file', 500);
    }
    $relativePath = 'uploads/employees/' . cid() . '/' . $employeeId . '/' . $uniqueName;

    $pdo->prepare(
        "INSERT INTO employee_documents (company_id, employee_id, document_type_id, file_name, file_path, mime_type, uploaded_at)
         VALUES (?, ?, ?, ?, ?, ?, NOW())"
    )->execute([cid(), $employeeId, $typeId, $fileName, $relativePath, $mimeType]);
    $newId = (int)$pdo->lastInsertId();

    if (!is_hr()) {
        notify_hr($pdo, 'document', 'New document uploaded', me()['name'] . ' uploaded ' . $fileName, ['employee_id' => $employeeId], (int)me()['id']);
    }

    $row = $pdo->prepare(documents_row_sql() . " WHERE ed.id = ? AND ed.company_id = ?");
    $row->execute([$newId, cid()]);
    json_response(['success' => true, 'data' => $row->fetch()], 201);
}

function documents_find(PDO $pdo, int $docId): ?array {
    $stmt = $pdo->prepare("SELECT * FROM employee_documents WHERE id = ? AND company_id = ?");
    $stmt->execute([$docId, cid()]);
    return $stmt->fetch() ?: null;
}

function documents_stream(int $docId, PDO $pdo): void {
    $doc = documents_find($pdo, $docId);
    if (!$doc) error_response('Document not found', 404);
    if (!is_hr() && (int)$doc['employee_id'] !== own_employee_id()) error_response('Forbidden. Insufficient permissions.', 403);

    $full = realpath(__DIR__ . '/../' . $doc['file_path']);
    $root = realpath(__DIR__ . '/../uploads');
    if (!$full || !$root || strpos($full, $root) !== 0 || !is_file($full)) error_response('File not found', 404);

    header('Content-Type: ' . ($doc['mime_type'] ?: 'application/octet-stream'));
    header('Content-Length: ' . filesize($full));
    header('Content-Disposition: inline; filename="' . str_replace('"', '', $doc['file_name']) . '"');
    header('X-Content-Type-Options: nosniff');
    header('Cache-Control: private, max-age=0');
    readfile($full);
    exit;
}

function documents_delete(int $employeeId, int $docId, PDO $pdo): void {
    $doc = documents_find($pdo, $docId);
    if (!$doc || (int)$doc['employee_id'] !== $employeeId) {
        error_response('Document not found', 404);
    }
    $full = realpath(__DIR__ . '/../' . $doc['file_path']);
    $root = realpath(__DIR__ . '/../uploads');
    if ($full && $root && strpos($full, $root) === 0 && is_file($full)) {
        @unlink($full);
    }
    $pdo->prepare("DELETE FROM employee_documents WHERE id = ? AND company_id = ?")->execute([$docId, cid()]);
    json_response(['success' => true, 'message' => 'Document deleted']);
}
