<?php
/**
 * Two-step approvals: when the owner switches the feature `approval_chain` on for a company, a request of an employee
 * who has a team head goes to that head FIRST. Only after the head approved does it reach HR for the final decision.
 *
 *   head_status  NULL      no head step (old request, feature off, or the employee has no head with an account)
 *                pending   waiting for the head          -> HR cannot decide yet (409), unless HR skips with a written reason
 *                approved  head said yes                 -> now HR decides (the head cannot finish it alone)
 *                rejected  head said no                  -> the request is rejected, HR is told
 *                skipped   HR decided without the head   -> only with a written reason, kept on record
 *
 * Applies to leave requests and to the general requests (expense, certificate, equipment, other). Profile changes and
 * attendance corrections stay HR-only as before.
 */

/** Request kinds that go through the head. */
function chain_request_types(): array { return ['expense', 'certificate', 'equipment', 'other']; }

/** 'pending' when a new request of this employee must go to the head first, otherwise null. */
function chain_start_status(PDO $pdo, int $employeeId): ?string {
    if (!function_exists('feature_enabled') || !feature_enabled($pdo, 'approval_chain')) return null;
    $s = $pdo->prepare(
        "SELECT m.id FROM employees e JOIN employees m ON m.id = e.manager_id AND m.company_id = e.company_id AND m.status != 'inactive'
         WHERE e.id = ? AND e.company_id = ? AND e.manager_id != e.id
           AND EXISTS (SELECT 1 FROM users u WHERE u.employee_id = m.id AND u.company_id = m.company_id AND u.status = 'active') LIMIT 1"
    );
    $s->execute([$employeeId, cid()]);
    return $s->fetchColumn() ? 'pending' : null;
}

function chain_mark(PDO $pdo, string $table, int $id, string $status, ?string $note): void {
    if (!in_array($table, ['leaves', 'requests'], true)) return;
    $pdo->prepare("UPDATE `$table` SET head_status = ?, head_by = ?, head_at = NOW(), head_note = ? WHERE id = ? AND company_id = ?")
        ->execute([$status, (int)me()['id'], $note !== null ? mb_substr($note, 0, 500) : null, $id, cid()]);
}

/**
 * Called by the review endpoints before they write a decision.
 * Returns 'normal' (carry on with the usual decision) or 'head_approved' (the head step is done and answered by this
 * function: the caller must only send the refreshed record back). Stops with 409/403 when the order would be broken.
 */
function chain_gate(PDO $pdo, string $table, array $row, string $new, array $body, string $what): string {
    $hs = $row['head_status'] ?? null;
    if ($hs === null || !in_array($new, ['approved', 'rejected'], true)) return 'normal';
    if (!feature_enabled($pdo, 'approval_chain')) return 'normal';        // switched off meanwhile: back to one step
    $employeeId = (int)$row['employee_id'];
    $id = (int)$row['id'];
    $note = isset($body['review_note']) ? trim((string)$body['review_note']) : '';
    $isHead = is_manager_of($pdo, $employeeId);

    if ($hs === 'pending') {
        if ($isHead) {
            if ($new === 'rejected') { chain_mark($pdo, $table, $id, 'rejected', $note ?: null); return 'normal'; }
            chain_mark($pdo, $table, $id, 'approved', $note ?: null);
            $headName = (string)(me()['name'] ?? '');
            notify_employee($pdo, $employeeId, 'chain_head_approved', 'Approved by your head',
                "$headName approved your $what. It is now with HR for the final decision.", [$table === 'leaves' ? 'leave_id' : 'request_id' => $id]);
            notify_hr($pdo, 'chain_head_approved', 'Needs your decision',
                "{$row['employee_name']}'s $what was approved by the team head and is waiting for HR.", [$table === 'leaves' ? 'leave_id' : 'request_id' => $id], (int)me()['id']);
            return 'head_approved';
        }
        if (is_hr()) {
            if (!empty($body['skip_head'])) {
                if (mb_strlen($note) < 3) error_response('Write the reason for deciding without the team head.', 422);
                chain_mark($pdo, $table, $id, 'skipped', $note);
                return 'normal';
            }
            error_response("This request is waiting for the team head's decision first.", 409);
        }
        return 'normal';
    }
    if ($hs === 'approved' && !is_hr()) {
        error_response('You already approved this. It is now with HR for the final decision.', 409);
    }
    if ($hs === 'rejected' && $new === 'approved' && !is_hr()) {
        error_response('The team head rejected this request.', 409);
    }
    return 'normal';
}
