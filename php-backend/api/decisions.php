<?php
/**
 * Fair decisions (feature `fair_decisions`): every adverse decision shows its reason, and the person can dispute it.
 *
 * Nothing is copied: the list is built from the real records (a rejected leave or request, a lost point, a payslip with
 * deductions), so a decision can never disagree with the data. Only disputes are stored. While the feature is on,
 * rejecting a leave or request needs a written reason (see decision_require_reason()).
 *
 *   GET  /decisions[?status=open|answered|none&employee_id=]      employee: own; manager: team + own; HR: everybody
 *   GET  /decisions/{kind}/{id}                                    one decision with its reason and dispute thread
 *   POST /decisions/{kind}/{id}/dispute   {message}                the affected employee (once per decision)
 *   PUT  /decisions/{kind}/{id}/respond   {status: upheld|reversed, response}   HR or the direct manager
 *   GET  /decisions/summary                                        (HR) open disputes, answered, reversed
 *
 * kind: leave | request | point | payslip.  "reversed" really reopens the decision: a leave / request goes back to
 * pending for a fresh answer, a lost point is voided. A payslip cannot be edited automatically, so HR is notified to fix it.
 */
const DECISION_KINDS = ['leave', 'request', 'point', 'payslip'];
const DECISION_WINDOW_DAYS = 120;

/** Used by leaves / requests when a reviewer rejects: with the feature on, a written reason is required. */
function decision_require_reason(PDO $pdo, string $newStatus, $note): void {
    if ($newStatus === 'rejected' && feature_enabled($pdo, 'fair_decisions') && trim((string)$note) === '') {
        error_response('Please write the reason, so the employee understands the decision.', 422);
    }
}

function handle_decisions(string $path, string $method, array $body): void {
    $pdo = getDB();
    $seg = explode('/', $path);
    $a = $seg[1] ?? '';
    if ($a === 'summary') { if ($method !== 'GET') error_response('Method not allowed', 405); require_hr(); decisions_summary($pdo); }
    if ($a === '') { if ($method !== 'GET') error_response('Method not allowed', 405); decisions_list($pdo); }
    if (!in_array($a, DECISION_KINDS, true) || !ctype_digit((string)($seg[2] ?? ''))) error_response('Endpoint not found: decisions/' . $a, 404);
    $kind = $a; $id = (int)$seg[2]; $act = $seg[3] ?? '';
    if ($act === '' && $method === 'GET') decisions_one($pdo, $kind, $id);
    if ($act === 'dispute' && $method === 'POST') decisions_dispute($pdo, $kind, $id, $body);
    if ($act === 'respond' && $method === 'PUT') decisions_respond($pdo, $kind, $id, $body);
    error_response('Method not allowed', 405);
}

/** Employee ids whose decisions the caller may see (null = everybody in the company). */
function decisions_scope(PDO $pdo): ?array {
    if (is_hr()) return null;
    $ids = [];
    if (own_employee_id() > 0) $ids[] = own_employee_id();
    if (has_direct_reports($pdo)) {
        $s = $pdo->prepare("SELECT id FROM employees WHERE company_id = ? AND manager_id = ?");
        $s->execute([cid(), own_employee_id()]);
        foreach ($s->fetchAll(PDO::FETCH_COLUMN) as $x) $ids[] = (int)$x;
    }
    return $ids ?: [-1];
}

function decisions_since(): string { return gmdate('Y-m-d', time() - DECISION_WINDOW_DAYS * 86400); }

/** All adverse decisions in scope, newest first, each with its dispute (if any). */
function decisions_collect(PDO $pdo, ?array $scope, ?int $only = null): array {
    $since = decisions_since();
    $filter = function (string $col) use ($scope, $only): array {
        $sql = ''; $p = [];
        if ($scope !== null) { $sql .= " AND $col IN (" . implode(',', array_map('intval', $scope)) . ")"; }
        if ($only) { $sql .= " AND $col = ?"; $p[] = $only; }
        return [$sql, $p];
    };
    $items = [];

    [$f, $fp] = $filter('l.employee_id');
    $s = $pdo->prepare("SELECT l.id, l.employee_id, l.start_date, l.end_date, l.review_note, l.reviewed_at, lt.name AS type_name, u.name AS by_name
        FROM leaves l LEFT JOIN leave_types lt ON lt.company_id = l.company_id AND lt.code = l.type LEFT JOIN users u ON u.id = l.reviewed_by
        WHERE l.company_id = ? AND l.status = 'rejected' AND DATE(l.reviewed_at) >= ? $f ORDER BY l.reviewed_at DESC LIMIT 100");
    $s->execute(array_merge([cid(), $since], $fp));
    foreach ($s->fetchAll() as $r) $items[] = ['kind' => 'leave', 'ref_id' => (int)$r['id'], 'employee_id' => (int)$r['employee_id'],
        'title' => 'Leave rejected: ' . ($r['type_name'] ?: 'Leave') . ' ' . $r['start_date'] . ' – ' . $r['end_date'],
        'reason_code' => null, 'reason_text' => $r['review_note'], 'decided_by' => $r['by_name'], 'decided_at' => $r['reviewed_at'], 'auto' => false];

    [$f, $fp] = $filter('r.employee_id');
    $s = $pdo->prepare("SELECT r.id, r.employee_id, r.title, r.review_note, r.reviewed_at, u.name AS by_name
        FROM requests r LEFT JOIN users u ON u.id = r.reviewed_by
        WHERE r.company_id = ? AND r.status = 'rejected' AND DATE(r.reviewed_at) >= ? $f ORDER BY r.reviewed_at DESC LIMIT 100");
    $s->execute(array_merge([cid(), $since], $fp));
    foreach ($s->fetchAll() as $r) $items[] = ['kind' => 'request', 'ref_id' => (int)$r['id'], 'employee_id' => (int)$r['employee_id'],
        'title' => 'Request rejected: ' . $r['title'], 'reason_code' => null, 'reason_text' => $r['review_note'],
        'decided_by' => $r['by_name'], 'decided_at' => $r['reviewed_at'], 'auto' => false];

    [$f, $fp] = $filter('p.employee_id');
    $s = $pdo->prepare("SELECT p.id, p.employee_id, p.date, p.color, p.reason, p.source, p.note, u.name AS by_name
        FROM points_ledger p LEFT JOIN users u ON u.id = p.created_by
        WHERE p.company_id = ? AND p.voided = 0 AND p.color IN ('red','black') AND p.date >= ? $f ORDER BY p.date DESC, p.id DESC LIMIT 150");
    $s->execute(array_merge([cid(), $since], $fp));
    foreach ($s->fetchAll() as $r) $items[] = ['kind' => 'point', 'ref_id' => (int)$r['id'], 'employee_id' => (int)$r['employee_id'],
        'title' => ucfirst($r['color']) . ' point on ' . $r['date'], 'reason_code' => 'why.' . $r['reason'], 'reason_text' => $r['note'],
        'decided_by' => $r['source'] === 'auto' ? null : $r['by_name'], 'decided_at' => $r['date'] . ' 00:00:00', 'auto' => $r['source'] === 'auto'];

    [$f, $fp] = $filter('p.employee_id');
    $s = $pdo->prepare("SELECT p.id, p.employee_id, p.month, p.year, p.deductions, p.breakdown, p.created_at FROM payroll p
        WHERE p.company_id = ? AND p.status != 'cancelled' AND p.deductions > 0 AND (p.year * 12 + p.month) >= ? $f ORDER BY p.year DESC, p.month DESC LIMIT 100");
    $s->execute(array_merge([cid(), (int)gmdate('Y') * 12 + (int)gmdate('n') - 5], $fp));
    foreach ($s->fetchAll() as $r) {
        $bd = json_decode((string)$r['breakdown'], true);
        $why = [];
        foreach (($bd['lines'] ?? []) as $l) if ((float)$l['amount'] < 0) $why[] = $l['label'] . ': ' . number_format(abs((float)$l['amount']), 2);
        $items[] = ['kind' => 'payslip', 'ref_id' => (int)$r['id'], 'employee_id' => (int)$r['employee_id'],
            'title' => sprintf('Deductions in %02d/%d: %s', $r['month'], $r['year'], number_format((float)$r['deductions'], 2)),
            'reason_code' => null, 'reason_text' => $why ? implode('; ', $why) : null, 'decided_by' => null,
            'decided_at' => $r['created_at'], 'auto' => true];
    }

    // disputes
    $d = $pdo->prepare("SELECT * FROM decision_disputes WHERE company_id = ?");
    $d->execute([cid()]);
    $disputes = [];
    foreach ($d->fetchAll() as $x) $disputes[$x['kind'] . ':' . $x['ref_id']] = $x;
    $names = [];
    $n = $pdo->prepare("SELECT id, CONCAT(first_name, ' ', last_name) FROM employees WHERE company_id = ?");
    $n->execute([cid()]);
    foreach ($n->fetchAll(PDO::FETCH_NUM) as $row) $names[(int)$row[0]] = $row[1];
    foreach ($items as &$it) {
        $x = $disputes[$it['kind'] . ':' . $it['ref_id']] ?? null;
        $it['employee_name'] = $names[$it['employee_id']] ?? '';
        $it['has_reason'] = $it['reason_code'] !== null || trim((string)$it['reason_text']) !== '';
        $it['dispute'] = $x ? ['id' => (int)$x['id'], 'message' => $x['message'], 'status' => $x['status'], 'response' => $x['response'],
                               'responded_at' => $x['responded_at'], 'created_at' => $x['created_at']] : null;
    }
    unset($it);
    usort($items, fn($a, $b) => strcmp((string)$b['decided_at'], (string)$a['decided_at']));
    return $items;
}

function decisions_list(PDO $pdo): void {
    $only = !empty($_GET['employee_id']) && is_hr() ? (int)$_GET['employee_id'] : null;
    $items = decisions_collect($pdo, decisions_scope($pdo), $only);
    $st = (string)($_GET['status'] ?? '');
    if ($st === 'open') $items = array_values(array_filter($items, fn($i) => $i['dispute'] && $i['dispute']['status'] === 'open'));
    elseif ($st === 'answered') $items = array_values(array_filter($items, fn($i) => $i['dispute'] && $i['dispute']['status'] !== 'open'));
    elseif ($st === 'none') $items = array_values(array_filter($items, fn($i) => !$i['dispute']));
    json_response(['success' => true, 'data' => $items]);
}

/** One decision the caller may see, or a 404. */
function decisions_find(PDO $pdo, string $kind, int $id): array {
    foreach (decisions_collect($pdo, decisions_scope($pdo)) as $it) {
        if ($it['kind'] === $kind && $it['ref_id'] === $id) return $it;
    }
    error_response('Decision not found', 404);
}

function decisions_one(PDO $pdo, string $kind, int $id): void {
    json_response(['success' => true, 'data' => decisions_find($pdo, $kind, $id)]);
}

function decisions_dispute(PDO $pdo, string $kind, int $id, array $body): void {
    $it = decisions_find($pdo, $kind, $id);
    if ($it['employee_id'] !== own_employee_id()) error_response('Only the person this decision is about can dispute it.', 403);
    $msg = trim((string)($body['message'] ?? ''));
    if (mb_strlen($msg) < 5 || mb_strlen($msg) > 2000) error_response('Please explain why you disagree (5 to 2000 characters).', 422);
    if ($it['dispute']) error_response('This decision was already disputed.', 409);
    $pdo->prepare("INSERT INTO decision_disputes (company_id, employee_id, kind, ref_id, message) VALUES (?,?,?,?,?)")
        ->execute([cid(), $it['employee_id'], $kind, $id, $msg]);
    $disputeId = (int)$pdo->lastInsertId();
    audit($pdo, 'dispute', 'decision', $disputeId, ['kind' => $kind, 'ref_id' => $id]);
    $data = ['kind' => $kind, 'ref_id' => $id];
    notify_manager_of($pdo, $it['employee_id'], 'decision', 'A decision was disputed', $it['employee_name'] . ' disagrees: ' . $it['title'], $data);
    notify_hr($pdo, 'decision', 'A decision was disputed', $it['employee_name'] . ' disagrees: ' . $it['title'], $data, (int)me()['id']);
    json_response(['success' => true, 'data' => decisions_find($pdo, $kind, $id)], 201);
}

function decisions_respond(PDO $pdo, string $kind, int $id, array $body): void {
    $it = decisions_find($pdo, $kind, $id);
    if (!$it['dispute']) error_response('Nobody has disputed this decision.', 409);
    if ($it['dispute']['status'] !== 'open') error_response('This dispute was already answered.', 409);
    $eid = $it['employee_id'];
    if (!can_review_for($pdo, $eid) || ($eid === own_employee_id() && !is_hr())) error_response('Forbidden. Only HR or the direct manager can answer.', 403);
    $status = (string)($body['status'] ?? '');
    if (!in_array($status, ['upheld', 'reversed'], true)) error_response('status must be upheld or reversed', 422);
    $resp = trim((string)($body['response'] ?? ''));
    if (mb_strlen($resp) < 3 || mb_strlen($resp) > 2000) error_response('Please write your answer (3 to 2000 characters).', 422);
    if ($status === 'reversed' && in_array($kind, ['point', 'payslip'], true) && !is_hr()) error_response('Only HR can reverse this kind of decision.', 403);

    $note = null;
    if ($status === 'reversed') {
        if ($kind === 'leave') {
            $pdo->prepare("UPDATE leaves SET status = 'pending', reviewed_by = NULL, reviewed_at = NULL WHERE id = ? AND company_id = ? AND status = 'rejected'")->execute([$id, cid()]);
            $note = 'The leave request is open again for a new decision.';
        } elseif ($kind === 'request') {
            $pdo->prepare("UPDATE requests SET status = 'pending', reviewed_by = NULL, reviewed_at = NULL WHERE id = ? AND company_id = ? AND status = 'rejected'")->execute([$id, cid()]);
            $note = 'The request is open again for a new decision.';
        } elseif ($kind === 'point') {
            $pdo->prepare("UPDATE points_ledger SET voided = 1 WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
            $note = 'The point was removed.';
        } else {
            $note = 'HR must now correct the payslip.';
            notify_hr($pdo, 'decision', 'Payslip deduction reversed', $it['employee_name'] . ': ' . $it['title'] . ' - please correct the payslip.', ['kind' => $kind, 'ref_id' => $id], (int)me()['id']);
        }
    }
    $pdo->prepare("UPDATE decision_disputes SET status = ?, response = ?, responded_by = ?, responded_at = NOW() WHERE id = ? AND company_id = ?")
        ->execute([$status, $resp, (int)me()['id'], $it['dispute']['id'], cid()]);
    audit($pdo, 'dispute_' . $status, 'decision', $it['dispute']['id'], ['kind' => $kind, 'ref_id' => $id]);
    notify_employee($pdo, $eid, 'decision', $status === 'reversed' ? 'Your dispute was accepted' : 'Your dispute was answered',
        $it['title'] . ' - ' . $resp, ['kind' => $kind, 'ref_id' => $id]);
    // After a reversal the decision is no longer adverse (so it leaves the list): answer from what we already hold
    $it['dispute'] = ['id' => $it['dispute']['id'], 'message' => $it['dispute']['message'], 'status' => $status, 'response' => $resp,
                      'responded_at' => gmdate('Y-m-d H:i:s'), 'created_at' => $it['dispute']['created_at']];
    $it['effect'] = $note;
    json_response(['success' => true, 'data' => $it]);
}

function decisions_summary(PDO $pdo): void {
    $s = $pdo->prepare("SELECT status, COUNT(*) FROM decision_disputes WHERE company_id = ? GROUP BY status");
    $s->execute([cid()]);
    $c = ['open' => 0, 'upheld' => 0, 'reversed' => 0];
    foreach ($s->fetchAll(PDO::FETCH_NUM) as $row) $c[$row[0]] = (int)$row[1];
    $answered = $c['upheld'] + $c['reversed'];
    json_response(['success' => true, 'data' => $c + ['answered' => $answered, 'reversal_rate' => $answered ? round($c['reversed'] / $answered * 100) : 0,
        'decisions_without_reason' => count(array_filter(decisions_collect($pdo, null), fn($i) => !$i['has_reason']))]]);
}
