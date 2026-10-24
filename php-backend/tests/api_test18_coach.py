"""Feature manager_coach: advice for this week from real patterns, scoped to what the caller manages.
Run:  python api_test18_coach.py http://127.0.0.1:8098
"""
import datetime
from feat_common import *

today = datetime.date.today()
iso = lambda back: (today - datetime.timedelta(days=back)).isoformat()

print("== setup")
hr, hr_uid, C = company("coach")
boss_tok, BOSS, _ = employee(hr, "boss", salary=15000, start_date=iso(900))
late_tok, LATE, _ = employee(hr, "latey", salary=8000, manager_id=BOSS, start_date=iso(400))
abs_tok, ABS, _ = employee(hr, "absent", salary=8000, manager_id=BOSS, start_date=iso(400))
ot_tok, OT, _ = employee(hr, "overtimer", salary=8000, manager_id=BOSS, start_date=iso(400))
new_tok, NEW, _ = employee(hr, "newbie", salary=8000, manager_id=BOSS, start_date=iso(80))
ann = today - datetime.timedelta(days=365 * 3)
ann_tok, ANN, _ = employee(hr, "annie", salary=8000, manager_id=BOSS, start_date=(ann.replace(year=ann.year) + datetime.timedelta(days=0)).isoformat())
out_tok, OUT, _ = employee(hr, "outsider", salary=8000, start_date=iso(400))
sql(f"UPDATE employees SET start_date = DATE_SUB(DATE_ADD(CURDATE(), INTERVAL 2 DAY), INTERVAL 3 YEAR) WHERE id = {ANN}")


def att(eid, back, status="present", late=0, ot=0):
    sql(f"INSERT INTO attendance (company_id, employee_id, date, status, late_minutes, overtime_minutes) VALUES ({C}, {eid}, '{iso(back)}', '{status}', {late}, {ot})")


for b in (1, 2, 3, 4): att(LATE, b, "late", 20)            # 4 late days in the last 2 weeks, none before
att(LATE, 16, "late", 10)                                    # 1 before
for b in (1, 5): att(ABS, b, "absent")
for b in (1, 2, 3, 4, 5): att(OT, b, "present", 0, 300)     # 25 overtime hours
att(OUT, 1, "late", 30); att(OUT, 2, "late", 30); att(OUT, 3, "late", 30); att(OUT, 4, "late", 30)
sql(f"INSERT INTO leaves (company_id, employee_id, type, start_date, end_date, days, status, created_at) VALUES ({C}, {LATE}, 'annual', '{(today + datetime.timedelta(days=9)).isoformat()}', '{(today + datetime.timedelta(days=10)).isoformat()}', 2, 'pending', DATE_SUB(UTC_TIMESTAMP(), INTERVAL 100 HOUR))")

print("== closed until switched on")
s, r = call("GET", "/coach/weekly", None, hr)
check("closed while off", s == 403 and r.get("code") == "feature_disabled", f"{s} {r}")
switch(C, manager_coach=True)

print("== HR sees the whole company")
s, r = call("GET", "/coach/weekly", None, hr)
check("company scope", s == 200 and r["scope"] == "company" and r["headcount"] >= 7, f"{s} {r.get('scope')} {r.get('headcount')}")
codes = {(t["code"], t["employeeId"]) for t in r["tips"]}
check("lateness rising for the late one", ("lateness_rising", LATE) in codes, f"{codes}")
check("lateness rising also for the outsider (HR sees all)", ("lateness_rising", OUT) in codes, f"{codes}")
check("absences flagged", ("absences", ABS) in codes, f"{codes}")
check("overtime flagged (25 h)", ("overtime_heavy", OT) in codes, f"{codes}")
check("probation ending soon for the newbie", ("probation_ending", NEW) in codes, f"{codes}")
check("anniversary this week", ("anniversary", ANN) in codes, f"{codes}")
check("approval waiting 100 h is high severity", any(t["code"] == "approvalsWaiting" or t["code"] == "approvals_waiting" for t in r["tips"]) and [t for t in r["tips"] if t["code"] == "approvals_waiting"][0]["severity"] == "high", f"{[t['code'] for t in r['tips']]}")
check("nobody was recognised: team-level tip", any(t["code"] == "no_recognition" for t in r["tips"]), "")
check("high severity first", r["tips"][0]["severity"] == "high", f"{r['tips'][0]}")
lt = [t for t in r["tips"] if t["code"] == "lateness_rising" and t["employeeId"] == LATE][0]
check("tip carries both languages and the numbers behind it", lt["titleAr"] and lt["actionEn"] and lt["data"]["lateDays"] == 4 and lt["data"]["previous"] == 1, f"{lt}")
check("summary counts match", sum(r["summary"].values()) == len(r["tips"]), f"{r['summary']}")

print("== a team lead sees only their team")
s, r = call("GET", "/coach/weekly", None, boss_tok)
check("team scope", s == 200 and r["scope"] == "team" and r["headcount"] == 5, f"{s} {r.get('scope')} {r.get('headcount')}")
ids = {t["employeeId"] for t in r["tips"] if t["employeeId"]}
check("tips only about the team, never the outsider", OUT not in ids and LATE in ids and OT in ids, f"{ids}")
s, r = call("GET", "/coach/weekly", None, late_tok)
check("a normal employee is refused", s == 403, f"{s}")

print("== recognition resets the tip")
for tok, to in ((boss_tok, LATE), (boss_tok, ABS), (boss_tok, OT), (boss_tok, NEW), (boss_tok, ANN)):
    call("POST", "/kudos", {"to_employee_id": to, "badge": "star", "message": "Great job this month"}, tok)
s, r = call("GET", "/coach/weekly", None, boss_tok)
check("no more 'not recognised' tip after thanking the team", not any(t["code"] == "no_recognition" for t in r["tips"]), f"{[t['code'] for t in r['tips']]}")

print("== off again closes it")
switch(C, manager_coach=False)
s, r = call("GET", "/coach/weekly", None, boss_tok)
check("closed for the manager too", s == 403 and r.get("code") == "feature_disabled", f"{s}")

finish()
