<?php
/**
 * Career path (feature `career_path`): levels with clear requirements and a plain "what is my next step".
 * A level asks for months of service, points (from the points system) and skills at a minimum proficiency (1-5).
 * Everything the employee sees is computed from real records, and "promote" uses the normal promotion flow
 * (position, optional new salary, notification), so the career path and the employee file never disagree.
 *
 *   GET    /career/me                              my level, next level, progress, blockers, rough ETA
 *   GET    /career/employee/{id}                   the same for one person (self, their manager, HR)
 *   GET    /career/team                            manager: their team; HR: everybody (readiness, blockers)
 *   GET    /career/levels                          the ladder (everyone)            POST/PUT/DELETE /career/levels[/id]   (HR)
 *   GET    /career/skills                          skill list (everyone)            POST/PUT/DELETE /career/skills[/id]   (HR)
 *   PUT    /career/employees/{id}/skills           {skills:[{skill_id, proficiency 0-5}]}   (HR or the direct manager; 0 removes)
 *   PUT    /career/employees/{id}/level            {level_id|null}                          (HR) place somebody on the ladder
 *   POST   /career/employees/{id}/promote          {salary?, effective_date?, note?}        (HR) move to the next level + promotion record
 */
require_once __DIR__ . '/employees.php';
require_once __DIR__ . '/../helpers/points.php';

function handle_career(string $path, string $method, array $body): void {
    $pdo = getDB();
    $seg = explode('/', $path);
    $a = $seg[1] ?? '';
    $id = ctype_digit((string)($seg[2] ?? '')) ? (int)$seg[2] : null;

    if ($a === 'me' && $method === 'GET') {
        $eid = own_employee_id();
        if ($eid <= 0) error_response('No employee record linked to this account', 404);
        json_response(['success' => true, 'data' => career_plan($pdo, $eid)]);
    }
    if ($a === 'employee' && $id && $method === 'GET') {
        career_assert_can_view($pdo, $id);
        json_response(['success' => true, 'data' => career_plan($pdo, $id)]);
    }
    if ($a === 'team' && $method === 'GET') career_team($pdo);
    if ($a === 'levels') career_levels_api($pdo, $id, $method, $body);
    if ($a === 'skills') career_skills_api($pdo, $id, $method, $body);
    if ($a === 'employees' && $id) {
        $act = $seg[3] ?? '';
        if ($act === 'skills' && $method === 'PUT') career_set_skills($pdo, $id, $body);
        if ($act === 'level' && $method === 'PUT') { require_hr(); career_set_level($pdo, $id, $body); }
        if ($act === 'promote' && $method === 'POST') { require_hr(); career_promote($pdo, $id, $body); }
    }
    error_response('Endpoint not found: career/' . $a, 404);
}

function career_assert_can_view(PDO $pdo, int $eid): void {
    if (!employee_in_company($pdo, $eid)) error_response('Employee not found', 404);
    if ($eid !== own_employee_id() && !is_hr() && !is_manager_of($pdo, $eid)) error_response('Forbidden. Insufficient permissions.', 403);
}

// ------------------------------------------------------------------ the ladder

function career_levels(PDO $pdo): array {
    $s = $pdo->prepare("SELECT * FROM career_levels WHERE company_id = ? ORDER BY rank_no");
    $s->execute([cid()]);
    $skills = career_skill_names($pdo);
    $out = [];
    foreach ($s->fetchAll() as $l) {
        $req = json_decode((string)$l['skills'], true);
        $req = is_array($req) ? $req : [];
        $out[] = ['id' => (int)$l['id'], 'rank_no' => (int)$l['rank_no'], 'name_en' => $l['name_en'], 'name_ar' => $l['name_ar'],
            'min_months' => (int)$l['min_months'], 'min_points' => (int)$l['min_points'],
            'skills' => array_values(array_map(fn($r) => ['skill_id' => (int)$r['skill_id'], 'min' => (int)$r['min'],
                'name_en' => $skills[(int)$r['skill_id']]['name_en'] ?? '?', 'name_ar' => $skills[(int)$r['skill_id']]['name_ar'] ?? null], $req))];
    }
    return $out;
}

function career_skill_names(PDO $pdo): array {
    $s = $pdo->prepare("SELECT id, name_en, name_ar FROM career_skills WHERE company_id = ?");
    $s->execute([cid()]);
    $out = [];
    foreach ($s->fetchAll() as $r) $out[(int)$r['id']] = $r;
    return $out;
}

function career_clean_level(PDO $pdo, array $b, ?array $cur): array {
    $name = trim((string)($b['name_en'] ?? ($cur['name_en'] ?? '')));
    if ($name === '' || mb_strlen($name) > 100) error_response('A level name is required', 422);
    $rank = isset($b['rank_no']) ? (int)$b['rank_no'] : (int)($cur['rank_no'] ?? 0);
    if ($rank < 1 || $rank > 99) error_response('Rank must be a number from 1 to 99', 422);
    $months = isset($b['min_months']) ? (int)$b['min_months'] : (int)($cur['min_months'] ?? 0);
    $points = isset($b['min_points']) ? (int)$b['min_points'] : (int)($cur['min_points'] ?? 0);
    if ($months < 0 || $months > 600 || $points < 0 || $points > 100000) error_response('Months or points out of range', 422);
    $skills = [];
    $rawSkills = array_key_exists('skills', $b) ? $b['skills'] : (json_decode((string)($cur['skills'] ?? ''), true) ?: []);
    $known = career_skill_names($pdo);
    foreach ((array)$rawSkills as $r) {
        $sid = (int)($r['skill_id'] ?? 0); $min = (int)($r['min'] ?? 0);
        if (!isset($known[$sid])) error_response('Unknown skill in the requirements', 422);
        if ($min < 1 || $min > 5) error_response('A skill level must be from 1 to 5', 422);
        $skills[$sid] = ['skill_id' => $sid, 'min' => $min];
    }
    $ar = array_key_exists('name_ar', $b) ? trim((string)$b['name_ar']) : (string)($cur['name_ar'] ?? '');
    return [$name, mb_substr($ar, 0, 100) ?: null, $rank, $months, $points, json_encode(array_values($skills))];
}

function career_levels_api(PDO $pdo, ?int $id, string $method, array $b): void {
    if ($method === 'GET' && $id === null) json_response(['success' => true, 'data' => career_levels($pdo)]);
    require_hr();
    if ($method === 'POST' && $id === null) {
        [$n, $ar, $rank, $m, $p, $sk] = career_clean_level($pdo, $b, null);
        $dup = $pdo->prepare("SELECT 1 FROM career_levels WHERE company_id = ? AND rank_no = ?");
        $dup->execute([cid(), $rank]);
        if ($dup->fetchColumn()) error_response('There is already a level with that rank', 409);
        $pdo->prepare("INSERT INTO career_levels (company_id, rank_no, name_en, name_ar, min_months, min_points, skills) VALUES (?,?,?,?,?,?,?)")->execute([cid(), $rank, $n, $ar, $m, $p, $sk]);
        audit($pdo, 'create', 'career_level', (int)$pdo->lastInsertId(), ['name' => $n, 'rank' => $rank]);
        json_response(['success' => true, 'data' => career_levels($pdo)], 201);
    }
    $s = $pdo->prepare("SELECT * FROM career_levels WHERE id = ? AND company_id = ?");
    $s->execute([(int)$id, cid()]);
    $cur = $s->fetch();
    if (!$cur) error_response('Level not found', 404);
    if ($method === 'PUT') {
        [$n, $ar, $rank, $m, $p, $sk] = career_clean_level($pdo, $b, $cur);
        $dup = $pdo->prepare("SELECT 1 FROM career_levels WHERE company_id = ? AND rank_no = ? AND id != ?");
        $dup->execute([cid(), $rank, $id]);
        if ($dup->fetchColumn()) error_response('There is already a level with that rank', 409);
        $pdo->prepare("UPDATE career_levels SET rank_no=?, name_en=?, name_ar=?, min_months=?, min_points=?, skills=? WHERE id=? AND company_id=?")->execute([$rank, $n, $ar, $m, $p, $sk, $id, cid()]);
        audit($pdo, 'update', 'career_level', $id, ['name' => $n]);
        json_response(['success' => true, 'data' => career_levels($pdo)]);
    }
    if ($method === 'DELETE') {
        $u = $pdo->prepare("SELECT COUNT(*) FROM employees WHERE company_id = ? AND career_level_id = ?");
        $u->execute([cid(), $id]);
        if ((int)$u->fetchColumn() > 0) error_response('People are on this level. Move them first.', 409);
        $pdo->prepare("DELETE FROM career_levels WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
        audit($pdo, 'delete', 'career_level', $id);
        json_response(['success' => true, 'data' => career_levels($pdo)]);
    }
    error_response('Method not allowed', 405);
}

function career_skills_api(PDO $pdo, ?int $id, string $method, array $b): void {
    if ($method === 'GET' && $id === null) json_response(['success' => true, 'data' => array_values(career_skill_names($pdo))]);
    require_hr();
    $name = trim((string)($b['name_en'] ?? ''));
    $ar = trim((string)($b['name_ar'] ?? ''));
    if ($method === 'POST' && $id === null) {
        if ($name === '' || mb_strlen($name) > 100) error_response('A skill name is required', 422);
        $dup = $pdo->prepare("SELECT 1 FROM career_skills WHERE company_id = ? AND name_en = ?");
        $dup->execute([cid(), $name]);
        if ($dup->fetchColumn()) error_response('That skill already exists', 409);
        $pdo->prepare("INSERT INTO career_skills (company_id, name_en, name_ar) VALUES (?,?,?)")->execute([cid(), $name, mb_substr($ar, 0, 100) ?: null]);
        json_response(['success' => true, 'data' => array_values(career_skill_names($pdo))], 201);
    }
    if (!$id || !isset(career_skill_names($pdo)[$id])) error_response('Skill not found', 404);
    if ($method === 'PUT') {
        if ($name === '' || mb_strlen($name) > 100) error_response('A skill name is required', 422);
        $dup = $pdo->prepare("SELECT 1 FROM career_skills WHERE company_id = ? AND name_en = ? AND id != ?");
        $dup->execute([cid(), $name, $id]);
        if ($dup->fetchColumn()) error_response('That skill already exists', 409);
        $pdo->prepare("UPDATE career_skills SET name_en = ?, name_ar = ? WHERE id = ? AND company_id = ?")->execute([$name, mb_substr($ar, 0, 100) ?: null, $id, cid()]);
        json_response(['success' => true, 'data' => array_values(career_skill_names($pdo))]);
    }
    if ($method === 'DELETE') {
        foreach (career_levels($pdo) as $l) foreach ($l['skills'] as $r) if ($r['skill_id'] === $id) error_response('A level still requires this skill. Remove it there first.', 409);
        $pdo->prepare("DELETE FROM employee_skills WHERE skill_id = ? AND company_id = ?")->execute([$id, cid()]);
        $pdo->prepare("DELETE FROM career_skills WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
        json_response(['success' => true, 'data' => array_values(career_skill_names($pdo))]);
    }
    error_response('Method not allowed', 405);
}

// ------------------------------------------------------------------ one person's plan

function career_months(?string $start): int {
    if (!$start) return 0;
    $d = (new DateTime($start))->diff(new DateTime(gmdate('Y-m-d')));
    return $d->invert ? 0 : $d->y * 12 + $d->m;
}

/** Points the person earned per month over the last 90 days (net, same weights as the score). */
function career_points_velocity(PDO $pdo, int $eid): float {
    $s = $pdo->prepare("SELECT color, COUNT(*) FROM points_ledger WHERE company_id = ? AND employee_id = ? AND voided = 0 AND date >= ? GROUP BY color");
    $s->execute([cid(), $eid, gmdate('Y-m-d', time() - 90 * 86400)]);
    $c = ['green' => 0, 'red' => 0, 'black' => 0];
    foreach ($s->fetchAll(PDO::FETCH_NUM) as $r) if (isset($c[$r[0]])) $c[$r[0]] = (int)$r[1];
    return round(($c['green'] * 10 - $c['red'] * 20 - $c['black'] * 50) / 3, 1);
}

function career_plan(PDO $pdo, int $eid): array {
    $e = $pdo->prepare("SELECT id, first_name, last_name, position, start_date, career_level_id FROM employees WHERE id = ? AND company_id = ?");
    $e->execute([$eid, cid()]);
    $emp = $e->fetch();
    $levels = career_levels($pdo);
    $current = null; $next = null;
    foreach ($levels as $l) if ($l['id'] === (int)$emp['career_level_id']) $current = $l;
    foreach ($levels as $l) { if ($current === null || $l['rank_no'] > $current['rank_no']) { $next = $l; break; } }

    $months = career_months($emp['start_date']);
    $pointsCfg = points_config($pdo);
    $pointsOn = (bool)$pointsCfg['enabled'];
    $score = $pointsOn ? (int)points_summary($pdo, $eid)['score'] : 0;
    $velocity = $pointsOn ? career_points_velocity($pdo, $eid) : 0.0;
    $mine = [];
    $m = $pdo->prepare("SELECT skill_id, proficiency FROM employee_skills WHERE employee_id = ? AND company_id = ?");
    $m->execute([$eid, cid()]);
    foreach ($m->fetchAll() as $r) $mine[(int)$r['skill_id']] = (int)$r['proficiency'];

    $plan = ['employee_id' => $eid, 'name' => trim($emp['first_name'] . ' ' . $emp['last_name']), 'position' => $emp['position'],
             'months_of_service' => $months, 'points_enabled' => $pointsOn, 'points_score' => $score, 'points_per_month' => $velocity,
             'current' => $current ? array_diff_key($current, ['skills' => 1]) : null, 'next' => null, 'readiness' => null,
             'ready' => false, 'blockers' => [], 'eta_months' => null,
             'my_skills' => array_map(fn($sid) => ['skill_id' => $sid, 'proficiency' => $mine[$sid]], array_keys($mine)),
             'top_level' => $next === null && $current !== null];
    if (!$next) return $plan;

    $parts = []; $blockers = []; $etaMonths = 0.0; $etaKnown = true;
    if ($next['min_months'] > 0) {
        $parts[] = min(1, $months / $next['min_months']);
        if ($months < $next['min_months']) { $left = $next['min_months'] - $months; $blockers[] = ['type' => 'tenure', 'need' => $next['min_months'], 'have' => $months, 'left' => $left]; $etaMonths = max($etaMonths, $left); }
    }
    if ($next['min_points'] > 0 && $pointsOn) {
        $parts[] = max(0, min(1, $score / $next['min_points']));
        if ($score < $next['min_points']) {
            $left = $next['min_points'] - $score;
            $blockers[] = ['type' => 'points', 'need' => $next['min_points'], 'have' => $score, 'left' => $left];
            if ($velocity > 0) $etaMonths = max($etaMonths, $left / $velocity); else $etaKnown = false;
        }
    }
    $skillRows = [];
    foreach ($next['skills'] as $r) {
        $have = $mine[$r['skill_id']] ?? 0;
        $parts[] = min(1, $have / $r['min']);
        $skillRows[] = ['skill_id' => $r['skill_id'], 'name_en' => $r['name_en'], 'name_ar' => $r['name_ar'], 'need' => $r['min'], 'have' => $have];
        if ($have < $r['min']) { $blockers[] = ['type' => 'skill', 'skill_id' => $r['skill_id'], 'name_en' => $r['name_en'], 'name_ar' => $r['name_ar'], 'need' => $r['min'], 'have' => $have]; $etaKnown = false; }
    }
    $pct = $parts ? (int)round(array_sum($parts) / count($parts) * 100) : 100;
    $plan['next'] = array_diff_key($next, ['skills' => 1]) + ['skills' => $skillRows];
    $plan['readiness'] = $pct;
    $plan['ready'] = !$blockers;
    $plan['blockers'] = $blockers;
    $plan['eta_months'] = !$blockers ? 0 : ($etaKnown ? (int)ceil($etaMonths) : null);
    return $plan;
}

function career_team(PDO $pdo): void {
    if (is_hr()) {
        $q = $pdo->prepare("SELECT id FROM employees WHERE company_id = ? AND status != 'inactive' ORDER BY first_name");
        $q->execute([cid()]);
    } elseif (has_direct_reports($pdo)) {
        $q = $pdo->prepare("SELECT id FROM employees WHERE company_id = ? AND manager_id = ? AND status != 'inactive' ORDER BY first_name");
        $q->execute([cid(), own_employee_id()]);
    } else error_response('Forbidden. Insufficient permissions.', 403);
    $rows = [];
    foreach ($q->fetchAll(PDO::FETCH_COLUMN) as $eid) {
        $p = career_plan($pdo, (int)$eid);
        $rows[] = ['employee_id' => $p['employee_id'], 'name' => $p['name'], 'position' => $p['position'], 'current' => $p['current'], 'next' => $p['next'] ? array_diff_key($p['next'], ['skills' => 1]) : null,
                   'readiness' => $p['readiness'], 'ready' => $p['ready'] && $p['next'] !== null, 'blockers' => count($p['blockers']), 'eta_months' => $p['eta_months'], 'top_level' => $p['top_level']];
    }
    json_response(['success' => true, 'data' => $rows]);
}

// ------------------------------------------------------------------ changes

function career_set_skills(PDO $pdo, int $eid, array $b): void {
    if (!employee_in_company($pdo, $eid)) error_response('Employee not found', 404);
    if (!is_hr() && !is_manager_of($pdo, $eid)) error_response('Forbidden. Only HR or the direct manager can record skills.', 403);
    if ($eid === own_employee_id() && !is_hr()) error_response('You cannot rate your own skills.', 403);
    $list = $b['skills'] ?? null;
    if (!is_array($list) || !$list) error_response('skills is required', 422);
    $known = career_skill_names($pdo);
    foreach ($list as $r) {
        $sid = (int)($r['skill_id'] ?? 0); $lv = (int)($r['proficiency'] ?? -1);
        if (!isset($known[$sid])) error_response('Unknown skill', 422);
        if ($lv < 0 || $lv > 5) error_response('Proficiency must be from 0 to 5', 422);
    }
    foreach ($list as $r) {
        $sid = (int)$r['skill_id']; $lv = (int)$r['proficiency'];
        if ($lv === 0) { $pdo->prepare("DELETE FROM employee_skills WHERE employee_id = ? AND skill_id = ? AND company_id = ?")->execute([$eid, $sid, cid()]); continue; }
        $pdo->prepare("INSERT INTO employee_skills (company_id, employee_id, skill_id, proficiency, verified_by) VALUES (?,?,?,?,?)
                       ON DUPLICATE KEY UPDATE proficiency = VALUES(proficiency), verified_by = VALUES(verified_by), updated_at = NOW()")
            ->execute([cid(), $eid, $sid, $lv, (int)me()['id']]);
    }
    audit($pdo, 'skills', 'employee', $eid, ['count' => count($list)]);
    json_response(['success' => true, 'data' => career_plan($pdo, $eid)]);
}

function career_set_level(PDO $pdo, int $eid, array $b): void {
    if (!employee_in_company($pdo, $eid)) error_response('Employee not found', 404);
    $lid = int_or_null($b['level_id'] ?? null);
    if ($lid !== null && !in_company($pdo, 'career_levels', $lid)) error_response('Unknown level', 422);
    $pdo->prepare("UPDATE employees SET career_level_id = ? WHERE id = ? AND company_id = ?")->execute([$lid, $eid, cid()]);
    audit($pdo, 'career_level', 'employee', $eid, ['level_id' => $lid]);
    json_response(['success' => true, 'data' => career_plan($pdo, $eid)]);
}

function career_promote(PDO $pdo, int $eid, array $b): void {
    if (!employee_in_company($pdo, $eid)) error_response('Employee not found', 404);
    $plan = career_plan($pdo, $eid);
    if (!$plan['next']) error_response('There is no higher level on the ladder.', 409);
    if (!$plan['ready'] && empty($b['force'])) error_response('Not ready yet: ' . count($plan['blockers']) . ' requirement(s) are still open.', 409);
    $salary = isset($b['salary']) && $b['salary'] !== '' ? (float)$b['salary'] : null;
    if ($salary !== null && $salary < 0) error_response('Salary cannot be negative', 422);
    $date = !empty($b['effective_date']) ? (string)$b['effective_date'] : att_now($pdo)->format('Y-m-d');
    $dd = DateTime::createFromFormat('Y-m-d', $date);
    if (!$dd || $dd->format('Y-m-d') !== $date) error_response('Date must be YYYY-MM-DD', 422);
    $nextId = (int)$plan['next']['id'];
    $pdo->prepare("INSERT INTO promotions (company_id, employee_id, type, to_position, to_salary, effective_date, applied, note, created_by) VALUES (?,?,?,?,?,?,0,?,?)")
        ->execute([cid(), $eid, 'promotion', $plan['next']['name_en'], $salary, $date, 'Career path: ' . ($b['note'] ?? 'requirements met'), (int)me()['id']]);
    $pdo->prepare("UPDATE employees SET career_level_id = ? WHERE id = ? AND company_id = ?")->execute([$nextId, $eid, cid()]);
    audit($pdo, 'career_promote', 'employee', $eid, ['level_id' => $nextId, 'salary' => $salary, 'date' => $date]);
    employees_apply_due_promotions($pdo);
    json_response(['success' => true, 'data' => career_plan($pdo, $eid)], 201);
}
