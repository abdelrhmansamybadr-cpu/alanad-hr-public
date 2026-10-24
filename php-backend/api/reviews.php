<?php
/**
 * Reviews API handler (company-scoped)
 *
 * HR creates and edits reviews. An employee can read their own reviews once they
 * have left the "draft" state.
 */
function handle_reviews(string $path, string $method, array $body): void {
    $pdo      = getDB();
    $segments = explode('/', $path);
    $sub      = $segments[1] ?? '';
    $id       = ($sub !== '' && is_numeric($sub)) ? intval($sub) : null;

    if ($id !== null) {
        switch ($method) {
            case 'GET':    reviews_get_one($id, $pdo); break;
            case 'PUT':    require_hr(); reviews_update($id, $body, $pdo); break;
            case 'DELETE': require_hr(); reviews_delete($id, $pdo); break;
            default:       error_response('Method not allowed', 405);
        }
    } else {
        switch ($method) {
            case 'GET':  reviews_list($pdo); break;
            case 'POST': require_hr(); reviews_create($body, $pdo); break;
            default:     error_response('Method not allowed', 405);
        }
    }
}

function reviews_select(): string {
    return "SELECT r.*,
                   CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
                   CONCAT(rev.first_name, ' ', rev.last_name) AS reviewer_name,
                   e.position AS employee_position,
                   e.department_id
            FROM reviews r
            JOIN employees e ON e.id = r.employee_id
            JOIN employees rev ON rev.id = r.reviewer_id";
}

function reviews_list(PDO $pdo): void {
    $where  = ['r.company_id = ?'];
    $params = [cid()];

    if (!is_hr()) {
        $where[]  = 'r.employee_id = ?';
        $params[] = own_employee_id();
        $where[]  = "r.status != 'draft'";
    } elseif (!empty($_GET['employee_id'])) {
        $where[]  = 'r.employee_id = ?';
        $params[] = intval($_GET['employee_id']);
    }
    if (!empty($_GET['status'])) { $where[] = 'r.status = ?';  $params[] = $_GET['status']; }
    if (!empty($_GET['period'])) { $where[] = 'r.period = ?';  $params[] = $_GET['period']; }

    $stmt = $pdo->prepare(reviews_select() . " WHERE " . implode(' AND ', $where) . " ORDER BY r.reviewed_at DESC");
    $stmt->execute($params);
    json_response(['success' => true, 'data' => $stmt->fetchAll()]);
}

function reviews_fetch(int $id, PDO $pdo): ?array {
    $stmt = $pdo->prepare(reviews_select() . " WHERE r.id = ? AND r.company_id = ?");
    $stmt->execute([$id, cid()]);
    return $stmt->fetch() ?: null;
}

function reviews_get_one(int $id, PDO $pdo): void {
    $review = reviews_fetch($id, $pdo);
    if (!$review) {
        error_response('Review not found', 404);
    }
    if (!is_hr() && ((int)$review['employee_id'] !== own_employee_id() || $review['status'] === 'draft')) {
        error_response('Forbidden. Insufficient permissions.', 403);
    }
    json_response(['success' => true, 'data' => $review]);
}

function reviews_create(array $body, PDO $pdo): void {
    $employeeId = intval($body['employee_id'] ?? 0);
    $reviewerId = intval($body['reviewer_id'] ?? 0) ?: own_employee_id();

    if (!$employeeId || !$reviewerId) {
        error_response('employee_id and reviewer_id are required');
    }
    if (!employee_in_company($pdo, $employeeId) || !employee_in_company($pdo, $reviewerId)) {
        error_response('One or both employees not found', 404);
    }
    $rating = isset($body['rating']) && $body['rating'] !== '' ? intval($body['rating']) : null;
    if ($rating !== null && ($rating < 1 || $rating > 5)) {
        error_response('Rating must be between 1 and 5', 422);
    }
    $status = $body['status'] ?? 'draft';
    if (!in_array($status, ['draft', 'submitted', 'approved'], true)) {
        error_response('Invalid status', 422);
    }

    $pdo->prepare(
        "INSERT INTO reviews
            (company_id, employee_id, reviewer_id, period, rating, goals, achievements, feedback, status, reviewed_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())"
    )->execute([
        cid(), $employeeId, $reviewerId,
        $body['period'] ?? null, $rating,
        $body['goals'] ?? null, $body['achievements'] ?? null, $body['feedback'] ?? null, $status,
    ]);

    $newId = (int)$pdo->lastInsertId();
    if ($status !== 'draft') {
        notify_employee($pdo, $employeeId, 'review', 'New performance review', 'A performance review was shared with you.', ['review_id' => $newId]);
    }
    reviews_get_one($newId, $pdo);
}

function reviews_update(int $id, array $body, PDO $pdo): void {
    $current = reviews_fetch($id, $pdo);
    if (!$current) {
        error_response('Review not found', 404);
    }

    $fields = [];
    $params = [];
    foreach (['period', 'rating', 'goals', 'achievements', 'feedback', 'status'] as $field) {
        if (array_key_exists($field, $body)) {
            if ($field === 'rating') {
                $v = $body[$field] === '' || $body[$field] === null ? null : intval($body[$field]);
                if ($v !== null && ($v < 1 || $v > 5)) error_response('Rating must be between 1 and 5', 422);
                $params[] = $v;
            } else {
                if ($field === 'status' && !in_array($body[$field], ['draft', 'submitted', 'approved'], true)) error_response('Invalid status', 422);
                $params[] = $body[$field];
            }
            $fields[] = "$field = ?";
        }
    }
    if (empty($fields)) {
        error_response('No fields to update');
    }

    $params[] = $id;
    $params[] = cid();
    $pdo->prepare("UPDATE reviews SET " . implode(', ', $fields) . " WHERE id = ? AND company_id = ?")->execute($params);

    if (isset($body['status']) && $current['status'] === 'draft' && $body['status'] !== 'draft') {
        notify_employee($pdo, (int)$current['employee_id'], 'review', 'New performance review', 'A performance review was shared with you.', ['review_id' => $id]);
    }
    reviews_get_one($id, $pdo);
}

function reviews_delete(int $id, PDO $pdo): void {
    if (!in_company($pdo, 'reviews', $id)) {
        error_response('Review not found', 404);
    }
    $pdo->prepare("DELETE FROM reviews WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
    json_response(['success' => true, 'message' => 'Review deleted']);
}
