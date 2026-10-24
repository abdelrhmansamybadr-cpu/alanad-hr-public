<?php
/**
 * Talent Pool API handler (company-scoped, HR only)
 *
 * The talent bank is the set of applications with status 'talent_pool'
 * grouped by department.
 */
function handle_talent_pool(string $path, string $method, array $body): void {
    $pdo      = getDB();
    $segments = explode('/', $path);
    $sub      = $segments[1] ?? '';
    require_hr();

    switch ($sub) {
        case 'overview':
            if ($method !== 'GET') error_response('Method not allowed', 405);
            talent_pool_overview($pdo);
            break;

        case 'candidates':
            // POST /talent-pool/candidates/:id/hire-as-employee
            if (($segments[3] ?? '') === 'hire-as-employee') {
                if ($method !== 'POST') error_response('Method not allowed', 405);
                talent_bank_hire(intval($segments[2] ?? 0), $body, $pdo);
                break;
            }
            if ($method !== 'GET') error_response('Method not allowed', 405);
            talent_pool_candidates($pdo);
            break;

        case 'talent-bank':
            talent_bank_route($segments, $method, $body, $pdo);
            break;

        case 'archive':
            if ($method !== 'POST') error_response('Method not allowed', 405);
            talent_pool_archive($body, $pdo);
            break;

        default:
            error_response('Not found', 404);
    }
}

function talent_pool_overview(PDO $pdo): void {
    // Matches the original API: [{departmentId, departmentName, jobs:[{jobId, jobTitle, counts:{status:n}}]}]
    $statuses = ['new', 'screening', 'interview', 'offer', 'hired', 'rejected', 'talent_pool'];

    $q = $pdo->prepare("SELECT job_id, status, COUNT(*) AS c FROM applications WHERE company_id = ? AND job_id IS NOT NULL GROUP BY job_id, status");
    $q->execute([cid()]);
    $counts = [];
    foreach ($q->fetchAll() as $r) {
        $counts[(int)$r['job_id']][$r['status']] = (int)$r['c'];
    }

    $jobsByDept = [];
    $q = $pdo->prepare("SELECT id, title, department_id FROM jobs WHERE company_id = ?");
    $q->execute([cid()]);
    foreach ($q->fetchAll() as $j) {
        $c = [];
        foreach ($statuses as $s) {
            $c[$s] = $counts[(int)$j['id']][$s] ?? 0;
        }
        $jobsByDept[(int)$j['department_id']][] = ['jobId' => (int)$j['id'], 'jobTitle' => $j['title'], 'counts' => $c];
    }

    $out = [];
    $q = $pdo->prepare("SELECT id, name FROM departments WHERE company_id = ? ORDER BY name");
    $q->execute([cid()]);
    foreach ($q->fetchAll() as $d) {
        $out[] = ['departmentId' => (int)$d['id'], 'departmentName' => $d['name'], 'jobs' => $jobsByDept[(int)$d['id']] ?? []];
    }
    json_response(['success' => true, 'data' => $out]);
}

function talent_pool_candidates(PDO $pdo): void {
    $where  = ['a.company_id = ?'];
    $params = [cid()];

    if (!empty($_GET['status'])) {
        $where[]  = 'a.status = ?';
        $params[] = $_GET['status'];
    } else {
        $where[]  = "a.status = 'talent_pool'";
    }
    if (!empty($_GET['job_id'])) {
        $where[]  = 'a.job_id = ?';
        $params[] = intval($_GET['job_id']);
    }

    $stmt = $pdo->prepare(
        "SELECT a.*, j.title AS job_title, d.name AS department_name
         FROM applications a
         LEFT JOIN jobs j ON j.id = a.job_id
         LEFT JOIN departments d ON d.id = COALESCE(j.department_id, a.direct_department_id)
         WHERE " . implode(' AND ', $where) . "
         ORDER BY a.applied_at DESC"
    );
    $stmt->execute($params);
    json_response(['success' => true, 'data' => $stmt->fetchAll()]);
}

function talent_pool_archive(array $body, PDO $pdo): void {
    $applicationId = intval($body['application_id'] ?? 0);
    if (!$applicationId) {
        error_response('application_id is required');
    }
    if (!in_company($pdo, 'applications', $applicationId)) {
        error_response('Application not found', 404);
    }

    $pdo->prepare("UPDATE applications SET status = 'talent_pool' WHERE id = ? AND company_id = ?")->execute([$applicationId, cid()]);

    $stmt = $pdo->prepare("SELECT a.*, j.title AS job_title FROM applications a LEFT JOIN jobs j ON j.id = a.job_id WHERE a.id = ? AND a.company_id = ?");
    $stmt->execute([$applicationId, cid()]);
    json_response(['success' => true, 'data' => $stmt->fetch()]);
}

// ---- Talent bank (department-grouped candidates, stored as applications with status 'talent_pool') ----

function talent_bank_select(): string {
    return "SELECT a.id, a.applicant_name AS name, COALESCE(a.email, '') AS email, a.phone,
                   a.direct_job_title AS job_title, a.direct_department_id AS department_id,
                   d.name AS department_name, a.cover_letter AS notes, a.status
            FROM applications a
            LEFT JOIN departments d ON d.id = a.direct_department_id";
}

function talent_bank_route(array $seg, string $method, array $body, PDO $pdo): void {
    $what = $seg[2] ?? '';
    $id   = (isset($seg[3]) && is_numeric($seg[3])) ? intval($seg[3]) : null;

    if ($what === 'departments' && $method === 'GET') {
        $q = $pdo->prepare(
            "SELECT d.id, d.name, COUNT(a.id) AS candidate_count
             FROM departments d
             LEFT JOIN applications a ON a.direct_department_id = d.id AND a.status = 'talent_pool' AND a.company_id = d.company_id
             WHERE d.company_id = ?
             GROUP BY d.id, d.name ORDER BY d.name"
        );
        $q->execute([cid()]);
        json_response(['success' => true, 'data' => $q->fetchAll()]);
    }

    if ($what === 'department' && $id !== null && $method === 'GET') {
        $stmt = $pdo->prepare(talent_bank_select() . " WHERE a.company_id = ? AND a.status = 'talent_pool' AND a.direct_department_id = ? ORDER BY a.applied_at DESC");
        $stmt->execute([cid(), $id]);
        json_response(['success' => true, 'data' => $stmt->fetchAll()]);
    }

    if ($what === 'candidates') {
        if ($id === null) {
            if ($method === 'GET') {
                $q = $pdo->prepare(talent_bank_select() . " WHERE a.company_id = ? AND a.status = 'talent_pool' ORDER BY a.applied_at DESC");
                $q->execute([cid()]);
                json_response(['success' => true, 'data' => $q->fetchAll()]);
            }
            if ($method === 'POST') {
                $name = trim($body['name'] ?? '');
                if ($name === '') error_response('name is required');
                $dep = int_or_null($body['department_id'] ?? null);
                if ($dep !== null && !in_company($pdo, 'departments', $dep)) error_response('Invalid department_id', 422);
                $pdo->prepare(
                    "INSERT INTO applications (company_id, applicant_name, email, phone, cover_letter, status, direct_department_id, direct_job_title)
                     VALUES (?, ?, ?, ?, ?, 'talent_pool', ?, ?)"
                )->execute([cid(), $name, $body['email'] ?? null, $body['phone'] ?? null, $body['notes'] ?? null, $dep, $body['job_title'] ?? null]);
                talent_bank_respond((int)$pdo->lastInsertId(), $pdo, 201);
            }
        } else {
            if ($method === 'GET') talent_bank_respond($id, $pdo);
            if ($method === 'PUT') {
                $map = ['name' => 'applicant_name', 'email' => 'email', 'phone' => 'phone',
                        'notes' => 'cover_letter', 'job_title' => 'direct_job_title', 'department_id' => 'direct_department_id'];
                $sets = []; $vals = [];
                foreach ($map as $in => $col) {
                    if (array_key_exists($in, $body)) {
                        $v = $body[$in] === '' ? null : $body[$in];
                        if ($in === 'department_id' && $v !== null && !in_company($pdo, 'departments', int_or_null($v))) error_response('Invalid department_id', 422);
                        $sets[] = "$col = ?"; $vals[] = $v;
                    }
                }
                if (!$sets) error_response('No fields to update');
                $vals[] = $id;
                $vals[] = cid();
                $pdo->prepare("UPDATE applications SET " . implode(', ', $sets) . " WHERE id = ? AND company_id = ? AND status = 'talent_pool'")->execute($vals);
                talent_bank_respond($id, $pdo);
            }
            if ($method === 'DELETE') {
                $pdo->prepare("DELETE FROM applications WHERE id = ? AND company_id = ? AND status = 'talent_pool'")->execute([$id, cid()]);
                json_response(['success' => true, 'message' => 'Candidate deleted']);
            }
        }
    }
    error_response('Not found', 404);
}

function talent_bank_respond(int $id, PDO $pdo, int $status = 200): void {
    $stmt = $pdo->prepare(talent_bank_select() . " WHERE a.id = ? AND a.company_id = ?");
    $stmt->execute([$id, cid()]);
    $row = $stmt->fetch();
    if (!$row) error_response('Candidate not found', 404);
    json_response(['success' => true, 'data' => $row], $status);
}

function talent_bank_hire(int $id, array $body, PDO $pdo): void {
    $stmt = $pdo->prepare("SELECT * FROM applications WHERE id = ? AND company_id = ?");
    $stmt->execute([$id, cid()]);
    $app = $stmt->fetch();
    if (!$app) error_response('Candidate not found', 404);

    $first = trim($body['first_name'] ?? '');
    $last  = trim($body['last_name'] ?? '');
    if ($first === '' || $last === '') {
        $parts = preg_split('/\s+/', trim($app['applicant_name']), 2);
        $first = $first ?: ($parts[0] ?? '');
        $last  = $last ?: ($parts[1] ?? '-');
    }
    $email = strtolower(trim($body['email'] ?? ($app['email'] ?? '')));
    if ($email === '') error_response('email is required to hire');

    $dup = $pdo->prepare("SELECT id FROM employees WHERE email = ? LIMIT 1");
    $dup->execute([$email]);
    if ($dup->fetch()) error_response('An employee with this email already exists', 409);

    $dep = int_or_null($body['department_id'] ?? null) ?? ($app['direct_department_id'] !== null ? (int)$app['direct_department_id'] : null);
    if ($dep !== null && !in_company($pdo, 'departments', $dep)) error_response('Invalid department_id', 422);

    $pdo->prepare(
        "INSERT INTO employees (company_id, first_name, last_name, email, phone, position, department_id, status, start_date, salary)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'active', ?, ?)"
    )->execute([
        cid(), $first, $last, $email, $body['phone'] ?? $app['phone'],
        $body['position'] ?? $app['direct_job_title'], $dep,
        $body['start_date'] ?? date('Y-m-d'),
        isset($body['salary']) && $body['salary'] !== '' ? floatval($body['salary']) : null,
    ]);
    $empId = (int)$pdo->lastInsertId();
    $pdo->prepare("UPDATE applications SET status = 'hired' WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
    json_response(['success' => true, 'data' => ['id' => $empId, 'candidate_id' => $id]], 201);
}
