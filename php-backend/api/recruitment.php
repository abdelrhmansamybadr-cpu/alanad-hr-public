<?php
/**
 * Recruitment API handler (company-scoped, HR only)
 * Handles /recruitment/jobs/*, /recruitment/applications/*, /jobs/*, /applications/*
 */
function handle_recruitment(string $path, string $method, array $body): void {
    $pdo      = getDB();
    $segments = explode('/', $path);
    require_hr();

    // Normalize: strip leading 'recruitment' if present, leaving jobs/applications as first segment
    if ($segments[0] === 'recruitment') {
        array_shift($segments);
        $segments = array_values($segments);
    }

    $resource = $segments[0] ?? '';
    $idSeg    = $segments[1] ?? '';
    $id       = ($idSeg !== '' && is_numeric($idSeg)) ? intval($idSeg) : null;

    switch ($resource) {
        case 'jobs':
            handle_recruitment_jobs($id, $method, $body, $pdo);
            break;
        case 'applications':
            handle_recruitment_applications($id, $method, $body, $pdo);
            break;
        default:
            error_response('Not found', 404);
    }
}

// ---- Jobs ----

function handle_recruitment_jobs(?int $id, string $method, array $body, PDO $pdo): void {
    if ($id !== null) {
        switch ($method) {
            case 'GET':    jobs_get_one($id, $pdo); break;
            case 'PUT':    jobs_update($id, $body, $pdo); break;
            case 'DELETE': jobs_delete($id, $pdo); break;
            default:       error_response('Method not allowed', 405);
        }
    } else {
        switch ($method) {
            case 'GET':  jobs_list($pdo); break;
            case 'POST': jobs_create($body, $pdo); break;
            default:     error_response('Method not allowed', 405);
        }
    }
}

function jobs_select(): string {
    return "SELECT j.*, d.name AS department_name, COUNT(a.id) AS applicant_count
            FROM jobs j
            LEFT JOIN departments d ON d.id = j.department_id
            LEFT JOIN applications a ON a.job_id = j.id";
}

function jobs_list(PDO $pdo): void {
    $where  = ['j.company_id = ?'];
    $params = [cid()];

    if (!empty($_GET['status'])) {
        $where[]  = 'j.status = ?';
        $params[] = $_GET['status'];
    }
    if (!empty($_GET['department_id'])) {
        $where[]  = 'j.department_id = ?';
        $params[] = intval($_GET['department_id']);
    }

    $stmt = $pdo->prepare(jobs_select() . " WHERE " . implode(' AND ', $where) . " GROUP BY j.id ORDER BY j.posted_at DESC");
    $stmt->execute($params);
    json_response(['success' => true, 'data' => $stmt->fetchAll()]);
}

function jobs_get_one(int $id, PDO $pdo): void {
    $stmt = $pdo->prepare(jobs_select() . " WHERE j.id = ? AND j.company_id = ? GROUP BY j.id");
    $stmt->execute([$id, cid()]);
    $job = $stmt->fetch();

    if (!$job) {
        error_response('Job not found', 404);
    }
    json_response(['success' => true, 'data' => $job]);
}

function jobs_valid_department(PDO $pdo, $value): ?int {
    $dep = int_or_null($value);
    if ($dep !== null && !in_company($pdo, 'departments', $dep)) error_response('Invalid department_id', 422);
    return $dep;
}

function jobs_create(array $body, PDO $pdo): void {
    $title = trim($body['title'] ?? '');
    if ($title === '') {
        error_response('Job title is required');
    }
    $status = $body['status'] ?? 'open';
    if (!in_array($status, ['open', 'closed'], true)) error_response('Invalid status', 422);

    $pdo->prepare(
        "INSERT INTO jobs (company_id, title, department_id, location, type, description, requirements, salary, status, posted_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())"
    )->execute([
        cid(), $title, jobs_valid_department($pdo, $body['department_id'] ?? null),
        $body['location'] ?? null, $body['type'] ?? null, $body['description'] ?? null,
        $body['requirements'] ?? null, $body['salary'] ?? null, $status,
    ]);

    jobs_get_one((int)$pdo->lastInsertId(), $pdo);
}

function jobs_update(int $id, array $body, PDO $pdo): void {
    if (!in_company($pdo, 'jobs', $id)) {
        error_response('Job not found', 404);
    }

    $fields = [];
    $params = [];
    foreach (['title', 'location', 'type', 'description', 'requirements', 'salary', 'status'] as $field) {
        if (array_key_exists($field, $body)) {
            $fields[] = "$field = ?";
            $params[]  = $body[$field];
        }
    }
    if (isset($body['status']) && !in_array($body['status'], ['open', 'closed'], true)) error_response('Invalid status', 422);
    if (array_key_exists('department_id', $body)) {
        $fields[] = 'department_id = ?';
        $params[]  = jobs_valid_department($pdo, $body['department_id']);
    }
    if (empty($fields)) {
        error_response('No fields to update');
    }

    $params[] = $id;
    $params[] = cid();
    $pdo->prepare("UPDATE jobs SET " . implode(', ', $fields) . " WHERE id = ? AND company_id = ?")->execute($params);
    jobs_get_one($id, $pdo);
}

function jobs_delete(int $id, PDO $pdo): void {
    if (!in_company($pdo, 'jobs', $id)) {
        error_response('Job not found', 404);
    }
    // Soft delete: close the job
    $pdo->prepare("UPDATE jobs SET status = 'closed' WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
    json_response(['success' => true, 'message' => 'Job closed']);
}

// ---- Applications ----

function handle_recruitment_applications(?int $id, string $method, array $body, PDO $pdo): void {
    if ($id !== null) {
        switch ($method) {
            case 'GET':    applications_get_one($id, $pdo); break;
            case 'PUT':    applications_update($id, $body, $pdo); break;
            case 'DELETE': applications_delete($id, $pdo); break;
            default:       error_response('Method not allowed', 405);
        }
    } else {
        switch ($method) {
            case 'GET':  applications_list($pdo); break;
            case 'POST': applications_create($body, $pdo); break;
            default:     error_response('Method not allowed', 405);
        }
    }
}

function applications_select(): string {
    return "SELECT a.*, j.title AS job_title, j.department_id, d.name AS department_name
            FROM applications a
            LEFT JOIN jobs j ON j.id = a.job_id
            LEFT JOIN departments d ON d.id = COALESCE(j.department_id, a.direct_department_id)";
}

function applications_list(PDO $pdo): void {
    $where  = ['a.company_id = ?', 'a.job_id IS NOT NULL'];   // talent-bank candidates live under /talent-pool
    $params = [cid()];

    if (!empty($_GET['job_id']))  { $where[] = 'a.job_id = ?'; $params[] = intval($_GET['job_id']); }
    if (!empty($_GET['status']))  { $where[] = 'a.status = ?'; $params[] = $_GET['status']; }

    $stmt = $pdo->prepare(applications_select() . " WHERE " . implode(' AND ', $where) . " ORDER BY a.applied_at DESC");
    $stmt->execute($params);
    json_response(['success' => true, 'data' => $stmt->fetchAll()]);
}

function applications_get_one(int $id, PDO $pdo): void {
    $stmt = $pdo->prepare(applications_select() . " WHERE a.id = ? AND a.company_id = ?");
    $stmt->execute([$id, cid()]);
    $app = $stmt->fetch();

    if (!$app) {
        error_response('Application not found', 404);
    }
    json_response(['success' => true, 'data' => $app]);
}

function applications_create(array $body, PDO $pdo): void {
    $name = trim($body['applicant_name'] ?? '');
    if ($name === '') {
        error_response('applicant_name is required');
    }
    $jobId = int_or_null($body['job_id'] ?? null);
    if ($jobId !== null && !in_company($pdo, 'jobs', $jobId)) error_response('Invalid job_id', 422);
    $dep = int_or_null($body['direct_department_id'] ?? null);
    if ($dep !== null && !in_company($pdo, 'departments', $dep)) error_response('Invalid direct_department_id', 422);

    $pdo->prepare(
        "INSERT INTO applications
            (company_id, job_id, applicant_name, email, phone, resume_url, cover_letter,
             status, applied_at, direct_department_id, direct_job_title)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'new', NOW(), ?, ?)"
    )->execute([
        cid(), $jobId, $name, $body['email'] ?? null, $body['phone'] ?? null,
        $body['resume_url'] ?? null, $body['cover_letter'] ?? null, $dep, $body['direct_job_title'] ?? null,
    ]);

    applications_get_one((int)$pdo->lastInsertId(), $pdo);
}

function applications_update(int $id, array $body, PDO $pdo): void {
    if (!in_company($pdo, 'applications', $id)) {
        error_response('Application not found', 404);
    }

    $fields = [];
    $params = [];
    foreach (['applicant_name', 'email', 'phone', 'resume_url', 'cover_letter', 'status', 'direct_job_title'] as $field) {
        if (array_key_exists($field, $body)) {
            $fields[] = "$field = ?";
            $params[]  = $body[$field];
        }
    }
    if (isset($body['status']) && !in_array($body['status'], ['new', 'screening', 'interview', 'offer', 'hired', 'rejected', 'talent_pool'], true)) {
        error_response('Invalid status', 422);
    }
    if (array_key_exists('direct_department_id', $body)) {
        $dep = int_or_null($body['direct_department_id']);
        if ($dep !== null && !in_company($pdo, 'departments', $dep)) error_response('Invalid direct_department_id', 422);
        $fields[] = 'direct_department_id = ?';
        $params[]  = $dep;
    }
    if (empty($fields)) {
        error_response('No fields to update');
    }

    $params[] = $id;
    $params[] = cid();
    $pdo->prepare("UPDATE applications SET " . implode(', ', $fields) . " WHERE id = ? AND company_id = ?")->execute($params);
    applications_get_one($id, $pdo);
}

function applications_delete(int $id, PDO $pdo): void {
    if (!in_company($pdo, 'applications', $id)) {
        error_response('Application not found', 404);
    }
    $pdo->prepare("DELETE FROM applications WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
    json_response(['success' => true, 'message' => 'Application deleted']);
}
