"""Feature group_dashboard: the owner sees every company side by side; nobody else does; every score explains itself.
Run:  python api_test21_portfolio.py http://127.0.0.1:8098
"""
import datetime
from feat_common import *

today = datetime.date.today()
iso = lambda back: (today - datetime.timedelta(days=back)).isoformat()

print("== setup: a group with two companies (Super Admin) and an unrelated company")
g_tok, g_uid, G1 = company("pf1")
sql(f"INSERT INTO company_groups (name, slug) VALUES ('PF {RUN}', 'pf-{RUN}')")
sql(f"UPDATE companies SET group_id = (SELECT id FROM company_groups WHERE slug = 'pf-{RUN}') WHERE id = {G1}")
sql(f"INSERT INTO group_admins (group_id, user_id) SELECT group_id, {g_uid} FROM companies WHERE id = {G1}")
sql(f"INSERT INTO platform_owners (user_id) VALUES ({g_uid})")      # only the owner creates companies
s, r = call("POST", "/group/companies", {"name": f"PF Two {RUN}", "ceoName": "CEO", "ceoEmail": f"ceo{RUN}@feat.test", "ceoPassword": PW}, g_tok)
G2 = r["id"]
sql(f"DELETE FROM platform_owners WHERE user_id = {g_uid}")
sql(f"UPDATE companies SET owner_managed = 0 WHERE id = {G2}")
x_tok, x_uid, X = company("pfx")                      # not in the group
emp_tok, EMP, _ = employee(g_tok, "worker", salary=8000)

# trouble in company two: lots of lateness, leavers, a manager with 13 reports, old pending leaves
sql(f"INSERT INTO employees (company_id, first_name, last_name, email, status, start_date) VALUES ({G2}, 'Big', 'Boss', 'bigboss{RUN}@feat.test', 'active', '2020-01-01')")
BOSS2 = int(sql_out(f"SELECT id FROM employees WHERE email = 'bigboss{RUN}@feat.test'"))
for i in range(13):
    sql(f"INSERT INTO employees (company_id, first_name, last_name, email, status, start_date, manager_id) VALUES ({G2}, 'W{i}', 'X', 'w{i}_{RUN}@feat.test', 'active', '2021-01-01', {BOSS2})")
for i in range(3):
    sql(f"INSERT INTO employees (company_id, first_name, last_name, email, status, start_date, termination_date) VALUES ({G2}, 'Gone{i}', 'X', 'gone{i}_{RUN}@feat.test', 'inactive', '2022-01-01', '{iso(20)}')")
w1 = int(sql_out(f"SELECT id FROM employees WHERE email = 'w0_{RUN}@feat.test'"))
for d in range(1, 11):
    sql(f"INSERT INTO attendance (company_id, employee_id, date, status, late_minutes) VALUES ({G2}, {w1}, '{iso(d)}', 'late', 25)")
sql(f"INSERT INTO leaves (company_id, employee_id, type, start_date, end_date, days, status, created_at) VALUES ({G2}, {w1}, 'annual', '{iso(-9)}', '{iso(-10)}', 2, 'pending', DATE_SUB(UTC_TIMESTAMP(), INTERVAL 100 HOUR))")
sql(f"INSERT INTO payroll (company_id, employee_id, month, year, base_salary, bonus, deductions, net_pay, status) VALUES ({G2}, {w1}, {today.month}, {today.year}, 5000, 0, 0, 5000, 'pending')")

print("== closed until the owner's home company has it on")
s, r = call("GET", "/portfolio", None, g_tok)
check("closed while off", s == 403 and r.get("code") == "feature_disabled", f"{s} {r}")
s, r = call("GET", "/portfolio", None, x_tok)
check("closed for an ordinary company admin", s == 403, f"{s}")

print("== a Super Admin sees only his group")
switch(G1, group_dashboard=True)
s, r = call("GET", "/portfolio", None, g_tok)
check("answers", s == 200 and r["mode"] == "super", f"{s} {r}")
ids = sorted(c["id"] for c in r["companies"])
check("exactly the two companies of the group, nobody else's", ids == sorted([G1, G2]), f"{ids}")
by = {c["id"]: c for c in r["companies"]}
check("company two needs attention first (sorted by score)", r["companies"][0]["id"] == G2 and by[G2]["attention"]["score"] > by[G1]["attention"]["score"], f"{[ (c['id'], c['attention']['score']) for c in r['companies']]}")
c2 = by[G2]
check("lateness counted (10 of 10 records)", c2["lateRate"] == 100.0 and c2["lateMinutes30d"] == 250, f"{c2['lateRate']} {c2['lateMinutes30d']}")
check("three leavers and turnover", c2["leavers90d"] == 3 and c2["turnover90d"] > 10, f"{c2['leavers90d']} {c2['turnover90d']}")
check("overloaded manager found (13 reports)", c2["overloadedManagers"] and c2["overloadedManagers"][0]["reports"] == 13, f"{c2['overloadedManagers']}")
check("old pending leave counted", c2["waitingApprovals"] == 1, f"{c2['waitingApprovals']}")
check("last payroll shown", c2["payrollNetLastMonth"] == 5000.0 and c2["payrollPeriod"] == f"{today.year:04d}-{today.month:02d}", f"{c2['payrollNetLastMonth']} {c2['payrollPeriod']}")
check("headcount counts only active people", c2["headcount"] == 14, f"{c2['headcount']}")
check("the score explains itself, in both languages", len(c2["attention"]["why"]) >= 4 and all(w["en"] and w["ar"] for w in c2["attention"]["why"]) and sum(w["points"] for w in c2["attention"]["why"]) in (c2["attention"]["score"], c2["attention"]["score"] + 1, c2["attention"]["score"] - 1), f"{c2['attention']}")
check("high level for the troubled company, low for the calm one", c2["attention"]["level"] in ("high", "medium") and by[G1]["attention"]["level"] == "low", f"{c2['attention']['level']} {by[G1]['attention']['level']}")
check("totals add up", r["totals"]["headcount"] == c2["headcount"] + by[G1]["headcount"] and r["totals"]["companies"] == 2 and r["totals"]["leavers90d"] == 3, f"{r['totals']}")

print("== nobody else can read it")
s, r = call("GET", "/portfolio", None, emp_tok)
check("an employee is refused", s == 403, f"{s}")
switch(X, group_dashboard=True)
s, r = call("GET", "/portfolio", None, x_tok)
check("a company admin who is neither owner nor Super Admin is refused even with the switch on", s == 403, f"{s} {r}")

print("== the platform owner sees every company")
oc = owner_company()
switch(oc, group_dashboard=True)
s, r = call("GET", "/portfolio", None, owner_token())
ids = {c["id"] for c in r["companies"]}
check("owner mode lists companies of every group", s == 200 and r["mode"] == "owner" and {G1, G2, X} <= ids, f"{s} {r.get('mode')}")

print("== off closes it again")
switch(G1, group_dashboard=False)
s, r = call("GET", "/portfolio", None, g_tok)
check("closed for the Super Admin when his home company has it off", s == 403 and r.get("code") == "feature_disabled", f"{s}")
s, r = call("GET", "/portfolio", None, owner_token())
check("the owner's own switch is independent", s == 200, f"{s}")

finish()
