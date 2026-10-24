<?php
/**
 * Owner dashboard (feature `group_dashboard`): one picture of every company the caller owns or is Super Admin of.
 *
 *   GET /portfolio     per company: people, last payroll, lateness, absence, leavers, overloaded managers, waiting approvals,
 *                      and a 0-100 attention score that always lists WHY (no black box), plus totals.
 *
 * Allowed: platform owners (every company) and group Super Admins (their group). It only reads; each company's data
 * stays in its own rows, the dashboard just counts them side by side.
 */
function handle_portfolio(string $path, string $method, array $body): void {
    $pdo = getDB();
    if ($method !== 'GET') error_response('Method not allowed', 405);
    $scope = owner_scope($pdo);
    if ($scope === null) error_response('Forbidden. This dashboard is for the owner of the companies.', 403);
    $ids = $scope['ids'];
    if ($ids === null) $ids = array_map('intval', $pdo->query("SELECT id FROM companies WHERE status = 'active' ORDER BY name")->fetchAll(PDO::FETCH_COLUMN));
    $rows = [];
    foreach ($ids as $cid_) {
        $c = company_get($pdo, (int)$cid_);
        if ($c && $c['status'] === 'active') $rows[] = portfolio_company($pdo, $c);
    }
    usort($rows, fn($a, $b) => $b['attention']['score'] <=> $a['attention']['score']);
    $tot = ['companies' => count($rows), 'headcount' => 0, 'payroll_net_last_month' => 0.0, 'leavers_90d' => 0, 'waiting_approvals' => 0, 'overloaded_managers' => 0];
    foreach ($rows as $r) {
        $tot['headcount'] += $r['headcount'];
        $tot['payroll_net_last_month'] += $r['payroll_net_last_month'];
        $tot['leavers_90d'] += $r['leavers_90d'];
        $tot['waiting_approvals'] += $r['waiting_approvals'];
        $tot['overloaded_managers'] += count($r['overloaded_managers']);
    }
    $tot['payroll_net_last_month'] = round($tot['payroll_net_last_month'], 2);
    json_response(['success' => true, 'data' => ['mode' => $scope['mode'], 'generated_at' => gmdate('Y-m-d H:i:s'), 'totals' => $tot, 'companies' => $rows]]);
}

function portfolio_company(PDO $pdo, array $c): array {
    $id = (int)$c['id'];
    $one = function (string $sql, array $p = []) use ($pdo) { $s = $pdo->prepare($sql); $s->execute($p); return $s->fetchColumn(); };
    $headcount = (int)$one("SELECT COUNT(*) FROM employees WHERE company_id = ? AND status != 'inactive'", [$id]);
    $since = gmdate('Y-m-d', time() - 30 * 86400);
    $att = $pdo->prepare("SELECT COUNT(*) AS n, SUM(status = 'late') AS late, SUM(status = 'absent') AS absent, SUM(CASE WHEN status = 'late' THEN late_minutes ELSE 0 END) AS late_min
                          FROM attendance WHERE company_id = ? AND date >= ?");
    $att->execute([$id, $since]);
    $a = $att->fetch();
    $n = max(1, (int)$a['n']);
    $lateRate = $a['n'] ? round((int)$a['late'] / $n * 100, 1) : 0.0;
    $absentRate = $a['n'] ? round((int)$a['absent'] / $n * 100, 1) : 0.0;
    $leavers = (int)$one("SELECT COUNT(*) FROM employees WHERE company_id = ? AND status = 'inactive' AND termination_date >= ?", [$id, gmdate('Y-m-d', time() - 90 * 86400)]);
    $hires = (int)$one("SELECT COUNT(*) FROM employees WHERE company_id = ? AND start_date >= ?", [$id, gmdate('Y-m-d', time() - 90 * 86400)]);
    $turnover = $headcount + $leavers > 0 ? round($leavers / ($headcount + $leavers) * 100, 1) : 0.0;

    $pay = $pdo->prepare("SELECT year, month, SUM(net_pay) AS net, COUNT(*) AS n FROM payroll WHERE company_id = ? AND status != 'cancelled' GROUP BY year, month ORDER BY year DESC, month DESC LIMIT 1");
    $pay->execute([$id]);
    $p = $pay->fetch();

    $waiting = (int)$one("SELECT (SELECT COUNT(*) FROM leaves WHERE company_id = ? AND status = 'pending' AND created_at < (UTC_TIMESTAMP() - INTERVAL 48 HOUR))
                                + (SELECT COUNT(*) FROM requests WHERE company_id = ? AND status = 'pending' AND created_at < (UTC_TIMESTAMP() - INTERVAL 48 HOUR))", [$id, $id]);

    // managers with a large team, or who leave many approvals waiting
    $mg = $pdo->prepare("SELECT m.id, CONCAT(m.first_name, ' ', m.last_name) AS name, COUNT(e.id) AS reports FROM employees m JOIN employees e ON e.manager_id = m.id AND e.status != 'inactive'
                         WHERE m.company_id = ? AND m.status != 'inactive' GROUP BY m.id HAVING reports > 12 ORDER BY reports DESC LIMIT 5");
    $mg->execute([$id]);
    $over = array_map(fn($r) => ['employee_id' => (int)$r['id'], 'name' => $r['name'], 'reports' => (int)$r['reports']], $mg->fetchAll());

    $why = []; $score = 0.0;
    $add = function (float $pts, string $en, string $ar) use (&$score, &$why) { if ($pts > 0) { $score += $pts; $why[] = ['points' => round($pts), 'en' => $en, 'ar' => $ar]; } };
    $add(min(30, $lateRate * 1.5), "$lateRate% of attendance records were late in 30 days", "$lateRate% من سجلات الحضور كانت متأخرة خلال 30 يوماً");
    $add(min(25, $absentRate * 3), "$absentRate% absence in 30 days", "$absentRate% غياب خلال 30 يوماً");
    $add(min(25, $turnover * 2), "$leavers people left in 90 days ($turnover% turnover)", "$leavers غادروا خلال 90 يوماً ($turnover% دوران)");
    $add(min(10, count($over) * 5), count($over) . " manager(s) with more than 12 direct reports", count($over) . " مدير لديهم أكثر من 12 مرؤوساً");
    $add(min(10, $waiting * 2), "$waiting request(s) waiting more than 2 days", "$waiting طلب ينتظر أكثر من يومين");
    $score = (int)min(100, round($score));

    return ['id' => $id, 'name' => $c['name'], 'currency' => $c['currency'], 'headcount' => $headcount,
        'payroll_period' => $p ? sprintf('%04d-%02d', $p['year'], $p['month']) : null, 'payroll_net_last_month' => $p ? round((float)$p['net'], 2) : 0.0,
        'late_rate' => $lateRate, 'absent_rate' => $absentRate, 'late_minutes_30d' => (int)$a['late_min'],
        'leavers_90d' => $leavers, 'hires_90d' => $hires, 'turnover_90d' => $turnover, 'waiting_approvals' => $waiting, 'overloaded_managers' => $over,
        'attention' => ['score' => $score, 'level' => $score >= 60 ? 'high' : ($score >= 30 ? 'medium' : 'low'), 'why' => $why]];
}
