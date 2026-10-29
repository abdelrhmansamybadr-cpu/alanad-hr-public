<?php
/**
 * Moving an employee or a department from one company of a group to another.
 *
 * Every company is its own tenant and history (attendance, payroll, leaves...) belongs to the company where it happened, so:
 *   - an EMPLOYEE is created in the target company (same details, same login) and the old record is closed as
 *     "Transferred to <company>" - its history stays where it was made;
 *   - a DEPARTMENT is moved as a whole (name, description); its people either move with it (each one transferred as above)
 *     or are left unassigned in the old company.
 * Who may do it: HR with full (not read-only) access to BOTH companies, and the "employees" / "departments" module in the target.
 */

/** Companies the caller may move things into (current company excluded): same group, full access, module allowed. */
function transfer_targets(PDO $pdo, string $module): array {
    $out = [];
    foreach (group_companies_for_user($pdo, me()) as $c) {
        if ((int)$c['id'] === cid() || ($c['status'] ?? '') !== 'active') continue;
        $a = $c['access'] ?? [];
        if (!empty($a['read_only'])) continue;
        if (($a['modules'] ?? null) !== null && !in_array($module, $a['modules'], true)) continue;
        $out[(int)$c['id']] = ['id' => (int)$c['id'], 'name' => $c['name']];
    }
    return array_values($out);
}

/** The target company (id, name) or a 403 - the caller must be allowed to move things into it. */
function transfer_target(PDO $pdo, $targetId, string $module): array {
    foreach (transfer_targets($pdo, $module) as $t) if ($t['id'] === (int)$targetId) return $t;
    error_response('You do not have full access to that company, so you cannot move things into it.', 403);
}

function transfer_company_name(PDO $pdo, int $id): string {
    $s = $pdo->prepare("SELECT name FROM companies WHERE id = ?");
    $s->execute([$id]);
    return (string)$s->fetchColumn();
}

/** Departments of the target company (to pick where a moved employee lands). */
function transfer_target_departments(PDO $pdo, int $targetId): array {
    transfer_target($pdo, $targetId, 'departments');
    $s = $pdo->prepare("SELECT id, name FROM departments WHERE company_id = ? ORDER BY name");
    $s->execute([$targetId]);
    return $s->fetchAll();
}

/**
 * Move one employee of the CURRENT company into $target (checks already done). Returns the new employee id.
 * $deptId is a department of the target company (or null).
 */
function transfer_employee_row(PDO $pdo, array $emp, array $target, ?int $deptId): int {
    $from = transfer_company_name($pdo, cid());
    $today = date('Y-m-d');

    // the same person must not already be in the target company
    if (!empty($emp['id_number'])) {
        $d = $pdo->prepare("SELECT 1 FROM employees WHERE company_id = ? AND id_number = ? AND status != 'inactive' LIMIT 1");
        $d->execute([$target['id'], $emp['id_number']]);
        if ($d->fetchColumn()) error_response($emp['first_name'] . ' ' . $emp['last_name'] . ' is already in ' . $target['name'] . ' (same ID number).', 409);
    }

    // e-mail is unique across the system: the old record gives it up, the new one keeps it
    $realMail = email_is_real($emp['email'] ?? '') ? $emp['email'] : null;
    $pdo->prepare("UPDATE employees SET email = ? WHERE id = ?")->execute([placeholder_email($pdo), $emp['id']]);

    $pdo->prepare(
        "INSERT INTO employees
            (company_id, first_name, last_name, email, phone, phone_key, position, department_id, shift_id, manager_id, status, start_date, salary,
             avatar, birth_date, gender, address, emergency_name, emergency_phone, contract_type, contract_start, contract_end, contract_months,
             nationality, id_number, bank_iban, iqama_expiry, iqama_renew_months, import_notes)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, 'active', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    )->execute([
        $target['id'], $emp['first_name'], $emp['last_name'], $realMail ?? placeholder_email($pdo), $emp['phone'], $emp['phone_key'], $emp['position'], $deptId,
        $emp['start_date'], $emp['salary'], $emp['avatar'], $emp['birth_date'], $emp['gender'], $emp['address'], $emp['emergency_name'], $emp['emergency_phone'],
        $emp['contract_type'], $emp['contract_start'], $emp['contract_end'], $emp['contract_months'],
        $emp['nationality'], $emp['id_number'], $emp['bank_iban'], $emp['iqama_expiry'], $emp['iqama_renew_months'], $emp['import_notes'],
    ]);
    $newId = (int)$pdo->lastInsertId();

    // the person's login moves with them (same e-mail / mobile / password), and is signed out everywhere once
    $u = $pdo->prepare("SELECT id FROM users WHERE employee_id = ? AND role = 'employee'");
    $u->execute([$emp['id']]);
    foreach ($u->fetchAll(PDO::FETCH_COLUMN) as $uid) {
        $pdo->prepare("UPDATE users SET company_id = ?, employee_id = ? WHERE id = ?")->execute([$target['id'], $newId, $uid]);
        $pdo->prepare("DELETE FROM sessions WHERE user_id = ?")->execute([$uid]);
    }

    // close the old record (its history stays in this company) and let go of what pointed at it
    $pdo->prepare("UPDATE employees SET status = 'inactive', termination_date = ?, termination_reason = ? WHERE id = ? AND company_id = ?")
        ->execute([$today, 'Transferred to ' . $target['name'], $emp['id'], cid()]);
    $pdo->prepare("UPDATE departments SET head_employee_id = NULL WHERE head_employee_id = ? AND company_id = ?")->execute([$emp['id'], cid()]);
    $pdo->prepare("UPDATE employees SET manager_id = NULL WHERE manager_id = ? AND company_id = ?")->execute([$emp['id'], cid()]);
    $pdo->prepare("DELETE FROM group_shares WHERE kind = 'employee' AND item_id = ?")->execute([$emp['id']]);
    audit($pdo, 'transfer_out', 'employee', (int)$emp['id'], ['to_company_id' => $target['id'], 'to' => $target['name'], 'new_employee_id' => $newId, 'from' => $from]);
    return $newId;
}

/** POST /group/transfer {kind: employee|department, id, target_company_id, department_id? (employee), move_members? (department)} */
function transfer_run(array $body, PDO $pdo): void {
    if (!empty(me()['access_read_only'])) error_response('You have read-only access to this company.', 403);
    $kind = (string)($body['kind'] ?? '');
    $id = int_or_null($body['id'] ?? null);
    if (!in_array($kind, ['employee', 'department'], true)) error_response('kind must be employee or department', 422);
    $target = transfer_target($pdo, $body['target_company_id'] ?? null, $kind === 'employee' ? 'employees' : 'departments');

    $pdo->beginTransaction();
    try {
        if ($kind === 'employee') {
            $s = $pdo->prepare("SELECT * FROM employees WHERE id = ? AND company_id = ?");
            $s->execute([$id, cid()]);
            $emp = $s->fetch();
            if (!$emp) error_response('Employee not found', 404);
            if ($emp['status'] === 'inactive') error_response('This employee is no longer active.', 422);
            $deptId = int_or_null($body['department_id'] ?? null);
            if ($deptId !== null) {
                $d = $pdo->prepare("SELECT 1 FROM departments WHERE id = ? AND company_id = ?");
                $d->execute([$deptId, $target['id']]);
                if (!$d->fetchColumn()) error_response('That department does not belong to the target company.', 422);
            }
            $newId = transfer_employee_row($pdo, $emp, $target, $deptId);
            $result = ['kind' => 'employee', 'target' => $target['name'], 'new_employee_id' => $newId];
        } else {
            $s = $pdo->prepare("SELECT * FROM departments WHERE id = ? AND company_id = ?");
            $s->execute([$id, cid()]);
            $dept = $s->fetch();
            if (!$dept) error_response('Department not found', 404);
            $from = transfer_company_name($pdo, cid());
            $name = $dept['name'];
            $dup = $pdo->prepare("SELECT 1 FROM departments WHERE company_id = ? AND name = ?");
            $dup->execute([$target['id'], $name]);
            if ($dup->fetchColumn()) $name .= ' (' . $from . ')';

            $mem = $pdo->prepare("SELECT * FROM employees WHERE department_id = ? AND company_id = ? AND status != 'inactive'");
            $mem->execute([$id, cid()]);
            $members = $mem->fetchAll();
            // people of OTHER companies that were using it through a share are taken out; shares go away
            $pdo->prepare("UPDATE employees SET department_id = NULL WHERE department_id = ? AND company_id != ?")->execute([$id, cid()]);
            $pdo->prepare("DELETE FROM group_shares WHERE kind = 'department' AND item_id = ?")->execute([$id]);
            // the department itself changes company; its head stays behind (employees do not move implicitly)
            $pdo->prepare("UPDATE departments SET company_id = ?, name = ?, head_employee_id = NULL WHERE id = ?")->execute([$target['id'], $name, $id]);
            $moved = 0;
            $move = !empty($body['move_members']);
            foreach ($members as $emp) {
                if ($move) { transfer_employee_row($pdo, $emp, $target, $id); $moved++; }
                else $pdo->prepare("UPDATE employees SET department_id = NULL WHERE id = ?")->execute([$emp['id']]);
            }
            audit($pdo, 'transfer_out', 'department', $id, ['to_company_id' => $target['id'], 'to' => $target['name'], 'people_moved' => $moved]);
            $result = ['kind' => 'department', 'target' => $target['name'], 'people_moved' => $moved];
        }
        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        throw $e;
    }
    json_response(['success' => true, 'data' => $result]);
}
