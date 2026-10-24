<?php
/**
 * Public holidays (company-scoped)
 *
 *   GET    /holidays?year=YYYY     list (everyone)
 *   POST   /holidays               {name, date}  or  {items: [{name, date}, ...]}   (HR)
 *   DELETE /holidays/{id}          (HR)
 */
function handle_holidays(string $path, string $method, array $body): void {
    $pdo = getDB();
    $sub = explode('/', $path)[1] ?? '';
    $id  = ($sub !== '' && is_numeric($sub)) ? intval($sub) : null;

    if ($id !== null) {
        if ($method !== 'DELETE') error_response('Method not allowed', 405);
        require_hr();
        if (!in_company($pdo, 'holidays', $id)) error_response('Holiday not found', 404);
        $pdo->prepare("DELETE FROM holidays WHERE id = ? AND company_id = ?")->execute([$id, cid()]);
        json_response(['success' => true, 'message' => 'Holiday deleted']);
    }

    switch ($method) {
        case 'GET':  holidays_list($pdo); break;
        case 'POST': require_hr(); holidays_create($body, $pdo); break;
        default:     error_response('Method not allowed', 405);
    }
}

function holidays_list(PDO $pdo): void {
    $year = !empty($_GET['year']) ? intval($_GET['year']) : (int)date('Y');
    $s = $pdo->prepare("SELECT id, name, date FROM holidays WHERE company_id = ? AND YEAR(date) = ? ORDER BY date");
    $s->execute([cid(), $year]);
    json_response(['success' => true, 'data' => $s->fetchAll()]);
}

function holidays_create(array $body, PDO $pdo): void {
    $items = isset($body['items']) && is_array($body['items']) ? $body['items'] : [$body];
    $ins = $pdo->prepare("INSERT INTO holidays (company_id, name, date) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name)");
    $n = 0;
    foreach ($items as $it) {
        $name = trim((string)($it['name'] ?? ''));
        $date = leaves_date_or_null($it['date'] ?? null);
        if ($name === '' || !$date) error_response('Each holiday needs a name and a date (YYYY-MM-DD)', 422);
        $ins->execute([cid(), mb_substr($name, 0, 200), $date]);
        $n++;
    }
    holidays_list($pdo);
}

function leaves_date_or_null($s): ?string {
    if (!is_string($s)) return null;
    $d = DateTime::createFromFormat('Y-m-d', substr($s, 0, 10));
    return ($d && $d->format('Y-m-d') === substr($s, 0, 10)) ? $d->format('Y-m-d') : null;
}
