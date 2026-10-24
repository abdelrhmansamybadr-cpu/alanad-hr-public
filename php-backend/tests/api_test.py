"""
End-to-end API tests: company separation, roles, and every feature.
Run against a private copy (never a real company):  python api_test.py http://127.0.0.1:8099
"""
import json, sys, urllib.request, urllib.error, uuid, datetime

_d = datetime.date.today() + datetime.timedelta(days=1)
while _d.weekday() != 0:          # next Monday (a working day with the default weekend fri,sat)
    _d += datetime.timedelta(days=1)
MONDAY = _d


def at(h, m=0, day=0):
    return (MONDAY + datetime.timedelta(days=day)).strftime('%Y-%m-%d') + f' {h:02d}:{m:02d}:00'

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8099") + "/api"
RUN = uuid.uuid4().hex[:6]
passed = failed = 0
failures = []


def call(method, path, body=None, token=None, raw=False, now=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    if now:
        req.add_header("X-Test-Now", now)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            txt = r.read().decode()
            return r.status, (json.loads(txt) if txt else None)
    except urllib.error.HTTPError as e:
        txt = e.read().decode()
        try:
            return e.code, json.loads(txt)
        except Exception:
            return e.code, txt


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  ok   {name}")
    else:
        failed += 1
        failures.append(name)
        print(f"  FAIL {name}  {extra}")


def section(t):
    print(f"\n== {t}")


# ------------------------------------------------------------------ setup
section("Company sign-up (two separate companies)")
PW = "Passw0rd!x"
s, a = call("POST", "/companies/register", {"company_name": f"Acme {RUN}", "name": "Alice Admin", "email": f"alice{RUN}@acme.test", "password": PW})
check("register company A -> 201", s == 201 and a and a.get("token"), (s, a))
A = a["token"]
check("company A has default branding", a["company"]["primaryColor"] == "#00617A" and a["company"]["name"].startswith("Acme"))
s, b = call("POST", "/companies/register", {"company_name": f"Globex {RUN}", "name": "Bob Boss", "email": f"bob{RUN}@globex.test", "password": PW})
check("register company B -> 201", s == 201 and b.get("token"))
B = b["token"]
check("companies are different", a["company"]["id"] != b["company"]["id"])
s, r = call("POST", "/companies/register", {"company_name": "X", "name": "X", "email": f"alice{RUN}@acme.test", "password": PW})
check("duplicate email rejected", s == 409, (s, r))
s, r = call("POST", "/companies/register", {"company_name": "X", "name": "X", "email": "weak@x.test", "password": "123"})
check("weak password rejected", s == 422, (s, r))

# ------------------------------------------------------- data in each company
section("Data is created per company")
s, d = call("POST", "/departments", {"name": "Engineering"}, A)
check("A creates department", s == 200 and d["id"], (s, d))
DEP_A = d["id"]
s, d = call("POST", "/departments", {"name": "Sales"}, B)
DEP_B = d["id"]
s, e = call("POST", "/employees", {"firstName": "Emma", "lastName": "Engineer", "email": f"emma{RUN}@acme.test", "position": "Developer", "departmentId": DEP_A, "salary": 6000, "birthDate": "1995-10-05"}, A)
check("A creates employee (201)", s == 201 and e["id"] and e.get("inviteCode"), (s, e))
EMP_A, CODE_A = e["id"], e["inviteCode"]
s, e2 = call("POST", "/employees", {"firstName": "Sam", "lastName": "Sales", "email": f"sam{RUN}@globex.test", "position": "Rep", "departmentId": DEP_B}, B)
EMP_B = e2["id"]

s, lst = call("GET", "/employees", token=A)
check("A sees only its own employees", s == 200 and [x["id"] for x in lst] == [EMP_A], lst)
s, lst = call("GET", "/employees", token=B)
check("B sees only its own employees", s == 200 and [x["id"] for x in lst] == [EMP_B])
s, r = call("GET", f"/employees/{EMP_B}", token=A)
check("A cannot read B's employee", s == 404, (s, r))
s, r = call("PUT", f"/employees/{EMP_B}", {"position": "hacked"}, A)
check("A cannot update B's employee", s == 404, (s, r))
s, r = call("DELETE", f"/employees/{EMP_B}", token=A)
check("A cannot delete B's employee", s == 404, (s, r))
s, r = call("GET", f"/departments/{DEP_B}", token=A)
check("A cannot read B's department", s == 404)
s, r = call("POST", "/employees", {"firstName": "Z", "lastName": "Z", "email": f"z{RUN}@acme.test", "departmentId": DEP_B}, A)
check("A cannot attach employee to B's department", s == 422, (s, r))
s, r = call("GET", "/departments", token=A)
check("departments list is scoped", [x["id"] for x in r] == [DEP_A])

# ------------------------------------------------------- employee activation
section("Employee activation with invite code")
s, r = call("POST", "/auth/employee/check-email", {"email": f"emma{RUN}@acme.test"})
check("check-email -> needs_activation", r.get("status") == "needs_activation", r)
s, r = call("POST", "/auth/employee/check-email", {"email": f"alice{RUN}@acme.test"})
check("check-email -> hr for admins", r.get("status") == "hr", r)
s, r = call("POST", "/auth/employee/check-email", {"email": "nobody@nowhere.test"})
check("check-email -> not_found", r.get("status") == "not_found")
s, r = call("POST", "/auth/employee/activate", {"email": f"emma{RUN}@acme.test", "code": "000000", "password": PW})
check("wrong code rejected", s == 422, (s, r))
s, r = call("POST", "/auth/employee/activate", {"email": f"emma{RUN}@acme.test", "code": CODE_A, "password": "short"})
check("weak password rejected on activation", s == 422)
s, r = call("POST", "/auth/employee/activate", {"email": f"emma{RUN}@acme.test", "code": CODE_A, "password": PW})
check("activation with code -> 201 + token", s == 201 and r.get("token"), (s, r))
E = r["token"]
check("employee token belongs to company A", r["company"]["id"] == a["company"]["id"])
s, r = call("POST", "/auth/employee/activate", {"email": f"emma{RUN}@acme.test", "code": CODE_A, "password": PW})
check("code cannot be reused", s in (409, 422), (s, r))
s, r = call("POST", "/auth/employee/forgot-password", {"email": f"emma{RUN}@acme.test"})
check("forgot-password leaks no token", "token" not in json.dumps(r).lower(), r)

# ---------------------------------------------------------------- roles
section("Role restrictions")
s, r = call("GET", "/employees", token=E)
check("employee cannot list employees", s == 403)
s, r = call("GET", "/stats", token=E)
check("employee cannot open HR stats", s == 403)
s, r = call("GET", "/hr-staff", token=E)
check("employee cannot open HR staff", s == 403)
s, r = call("GET", "/payroll", token=E)
check("employee can open own payroll list", s == 200 and r == [])
s, r = call("GET", "/directory", token=E)
check("employee can open directory", s == 200 and len(r) == 1)
s, r = call("PUT", "/company", {"name": "Hacked"}, E)
check("employee cannot edit company", s == 403)
s, r = call("GET", "/company", token=E)
check("employee can read company branding", s == 200 and r["name"].startswith("Acme"))
s, r = call("GET", "/employees", token=None)
check("anonymous blocked", s == 401)

# ------------------------------------------------------------ company settings
section("Company settings / branding")
s, r = call("PUT", "/company", {"primaryColor": "#0EA5E9", "accentColor": "#F97316", "weekendDays": ["fri", "sat"], "currency": "usd", "lateGraceMinutes": 10}, A)
check("admin updates branding", s == 200 and r["primaryColor"] == "#0EA5E9" and r["currency"] == "USD" and r["lateGraceMinutes"] == 10, (s, r))
s, r = call("PUT", "/company", {"primaryColor": "red"}, A)
check("invalid colour rejected", s == 422)
s, r = call("PUT", "/company", {"modules": ["employees", "leaves", "attendance"]}, A)
check("admin sets enabled modules", s == 200 and r["modules"] == ["employees", "leaves", "attendance"], r)
s, r = call("GET", "/payroll", token=A)
check("disabled module (payroll) is closed", s == 403, (s, r))
s, r = call("PUT", "/company", {"modules": None}, A)
check("admin re-enables all modules", s == 200 and r["modules"] is None)
s, r = call("GET", "/company", token=B)
check("company B branding untouched", r["primaryColor"] == "#00617A")

# ----------------------------------------------------------- holidays + leaves
section("Holidays, leave types, balances, approvals")
s, r = call("POST", "/holidays", {"items": [{"name": "Test holiday", "date": "2031-03-05"}]}, A)
check("HR adds holiday", s == 200 and any(h["date"] == "2031-03-05" for h in call("GET", "/holidays?year=2031", token=A)[1]))
s, r = call("GET", "/holidays?year=2031", token=B)
check("holiday not visible to company B", r == [])
s, types = call("GET", "/leave-types", token=E)
check("employee sees leave types", s == 200 and {t["code"] for t in types} >= {"annual", "sick"}, types)
s, r = call("POST", "/leave-types", {"name": "Study leave", "daysPerYear": 5}, A)
check("admin adds leave type", s == 201 and r["code"] == "study_leave", (s, r))
s, r = call("POST", "/leave-types", {"name": "Study"}, E)
check("employee cannot add leave type", s == 403)

# 2031-03-03 is Monday. weekend fri,sat => Mon..Thu working; 5 Mar is a holiday
s, r = call("POST", "/leaves", {"type": "annual", "startDate": "2031-03-03", "endDate": "2031-03-09", "reason": "trip"}, E)
check("employee requests leave -> 201", s == 201, (s, r))
LV = r["id"] if s == 201 else 0
# Mon 3, Tue 4, (Wed 5 holiday), Thu 6, (Fri 7, Sat 8 weekend), Sun 9 => 4 working days: 3,4,6,9. verify precisely below
s, one = call("GET", f"/leaves/{LV}", token=E)
check("working-days count is exact (3,4,6,9 = 4 days)", one["days"] == 4 if s == 200 else False, one)
s, r = call("POST", "/leaves", {"type": "annual", "startDate": "2031-03-04", "endDate": "2031-03-04"}, E)
check("overlapping request rejected", s == 409, (s, r))
s, r = call("POST", "/leaves", {"type": "annual", "startDate": "2031-04-07", "endDate": "2031-08-30"}, E)
check("over-balance request rejected", s == 422, (s, r))
s, r = call("POST", "/leaves", {"type": "nonsense", "startDate": "2031-04-07", "endDate": "2031-04-08"}, E)
check("unknown leave type rejected", s == 422)
s, r = call("PUT", f"/leaves/{LV}", {"status": "approved"}, E)
check("employee cannot approve own leave", s == 403, (s, r))
s, r = call("GET", "/leaves?status=pending", token=A)
check("HR sees the pending leave", s == 200 and any(x["id"] == LV for x in r))
s, r = call("GET", "/leaves", token=B)
check("company B cannot see A's leave", r == [])
s, r = call("PUT", f"/leaves/{LV}", {"status": "approved"}, B)
check("company B cannot approve A's leave", s == 404, (s, r))
s, r = call("PUT", f"/leaves/{LV}", {"status": "approved", "reviewNote": "Enjoy"}, A)
check("HR approves leave", s == 200 and r["status"] == "approved", (s, r))
s, bal = call("GET", "/leaves/balance?year=2031", token=E)
ann = next(x for x in bal["balances"] if x["code"] == "annual")
check("balance reflects approved days (21-4=17)", ann["used"] == 4 and ann["remaining"] == 17, ann)

# ----------------------------------------------------------- notifications
section("Notifications")
s, n = call("GET", "/notifications", token=E)
titles = [x["title"] for x in n["items"]] if s == 200 else []
check("employee notified about leave decision", any("Leave request approved" in t for t in titles), titles)
s, n = call("GET", "/notifications", token=A)
check("HR notified about the new employee document/leave", s == 200 and n["unreadCount"] >= 1, n)
s, r = call("POST", "/notifications/read", {"all": True}, E)
check("mark all read", s == 200 and r["unreadCount"] == 0, r)
s, r = call("GET", "/notifications", token=B)
check("company B has no notifications from A", r["items"] == [] or all("Acme" not in json.dumps(x) for x in r["items"]))

# ------------------------------------------------------------- attendance
section("Attendance (check-in / out, rules)")
s, t = call("GET", "/attendance/today", token=E, now=at(8, 50))
check("today: state ready", s == 200 and t["state"] == "ready", (s, t))
# location rule far from where we'll check in
s, r = call("POST", "/attendance-rules", {"name": "Office", "isActive": True, "locationEnabled": True, "locationLat": 30.0444, "locationLng": 31.2357, "locationRadiusKm": 0.2}, A)
check("admin creates active rule", s == 200 and r["isActive"] in (1, True), (s, r))
s, r = call("POST", "/attendance/check-in", {}, E)
check("check-in needs location", s == 422, (s, r))
s, r = call("POST", "/attendance/check-in", {"lat": 31.0, "lng": 32.0}, E)
check("check-in far away rejected", s == 422 and "away" in json.dumps(r), (s, r))
s, r = call("POST", "/attendance/check-in", {"lat": 30.0445, "lng": 31.2358}, E, now=at(9, 5))
check("check-in inside radius OK (on time)", s == 201 and r["status"] == "present", (s, r))
s, r = call("POST", "/attendance/check-in", {"lat": 30.0445, "lng": 31.2358}, E, now=at(9, 6))
check("double check-in rejected", s == 409)
s, r = call("POST", "/attendance/check-out", {"lat": 30.0445, "lng": 31.2358}, E, now=at(17, 5))
check("check-out OK", s == 200 and r["checkOut"] and r["status"] == "present", (s, r))
s, r = call("GET", "/attendance/board?date=" + at(9)[:10], token=A, now=at(18))
check("HR live board", s == 200 and r["total"] == 1 and r["counts"]["present"] + r["counts"]["late"] + r["counts"]["half_day"] >= 1, (s, r))
s, r = call("GET", "/attendance/board", token=E)
check("employee cannot open the live board", s in (403,), (s, r))
s, r = call("GET", "/attendance/summary", token=E, now=at(18))
check("monthly summary", s == 200 and r["presentDays"] + r["lateDays"] + r["halfDays"] >= 1, (s, r))

# ---------------------------------------------------------- requests + team
section("Requests, manager approvals, team")
s, mgr = call("POST", "/employees", {"firstName": "Mona", "lastName": "Manager", "email": f"mona{RUN}@acme.test", "position": "Team lead", "departmentId": DEP_A}, A)
MGR = mgr["id"]
s, r = call("PUT", f"/employees/{EMP_A}", {"managerId": MGR}, A)
check("HR sets Emma's manager", s == 200 and r["managerId"] == MGR, (s, r))
s, act = call("POST", "/auth/employee/activate", {"email": f"mona{RUN}@acme.test", "code": mgr["inviteCode"], "password": PW})
M = act["token"]
s, r = call("GET", "/team", token=M)
check("team lead sees direct reports", s == 200 and [x["id"] for x in r] == [EMP_A], (s, r))
s, r = call("GET", "/team", token=E)
check("non-lead cannot open team", s == 403)
s, r = call("POST", "/requests", {"type": "expense", "title": "Taxi to client", "amount": 120}, E)
check("employee files expense request", s == 201, (s, r))
RQ = r["id"]
s, r = call("POST", "/requests", {"type": "expense", "title": "No amount"}, E)
check("expense needs amount", s == 422)
s, r = call("GET", "/requests?scope=team", token=M)
check("manager sees the report's request", s == 200 and any(x["id"] == RQ for x in r), (s, r))
s, r = call("PUT", f"/requests/{RQ}", {"status": "approved", "reviewNote": "ok"}, M)
check("manager approves request", s == 200 and r["status"] == "approved", (s, r))
s, r = call("PUT", f"/requests/{RQ}", {"status": "rejected"}, E)
check("employee cannot change a handled request", s in (403, 409))
s, r = call("POST", "/leaves", {"type": "casual", "startDate": "2031-05-04", "endDate": "2031-05-04"}, E)
LV2 = r["id"]
s, r = call("PUT", f"/leaves/{LV2}", {"status": "approved"}, M)
check("manager approves report's leave", s == 200 and r["status"] == "approved", (s, r))
s, r = call("GET", "/leaves?scope=team", token=M)
check("manager team leaves", s == 200 and any(x["id"] == LV2 for x in r))
s, r = call("GET", "/leaves", token=M)
check("manager's own leave list excludes team", s == 200 and all(x["employeeId"] == MGR for x in r))

# -------------------------------------------------------- payroll + stats
section("Payroll run, payslips, dashboards")
s, r = call("POST", "/payroll/generate", {"month": "2031-01"}, A)
check("generate payroll for all with a salary", s == 200 and r["created"] == 1, (s, r))
s, r = call("POST", "/payroll/generate", {"month": "2031-01"}, A)
check("generate twice creates nothing new", r["created"] == 0)
s, r = call("PUT", "/payroll/pay-all", {"month": "2031-01"}, A)
check("pay all", s == 200 and r["paid"] == 1, (s, r))
s, r = call("GET", "/payroll", token=E)
check("employee sees own payslip", s == 200 and len(r) == 1 and r[0]["status"] == "paid" and r[0]["month"] == "2031-01", (s, r))
s, n = call("GET", "/notifications", token=E)
check("employee notified: payslip", any("payslip" in x["title"].lower() for x in n["items"]))
s, r = call("GET", "/payroll", token=B)
check("company B sees no payroll of A", r == [])
s, r = call("GET", "/stats", token=A)
check("HR dashboard", s == 200 and r["totalEmployees"] == 2 and "attendanceTrend" in r and "upcomingEvents" in r, (s, r))
s, r = call("GET", "/stats/me", token=E)
check("employee home stats", s == 200 and "leaveBalances" in r if s == 200 else False, (s, r))

# ------------------------------------------------------------ HR staff
section("HR staff")
s, r = call("POST", "/hr-staff", {"name": "Hana HR", "email": f"hana{RUN}@acme.test", "password": PW, "role": "hr_manager"}, A)
check("admin adds HR manager", s == 201, (s, r))
HRM = r["id"]
s, lg = call("POST", "/auth/login", {"email": f"hana{RUN}@acme.test", "password": PW})
H = lg["token"]
s, r = call("POST", "/hr-staff", {"name": "X", "email": "x@x.test", "password": PW}, H)
check("HR manager cannot add staff", s == 403)
s, r = call("PUT", f"/hr-staff/{HRM}", {"permissions": [{"module": "payroll", "enabled": False}]}, A)
check("admin restricts a module for the HR manager", s == 200)
s, r = call("GET", "/payroll", token=H)
check("restricted module is blocked for that HR manager", s == 403, (s, r))
s, r = call("GET", "/employees", token=H)
check("other modules still open for HR manager", s == 200)

# ------------------------------------------------------- brute force / misc
section("Security")
for i in range(9):
    call("POST", "/auth/login", {"email": f"ghost{RUN}@x.test", "password": "wrong"})
s, r = call("POST", "/auth/login", {"email": f"ghost{RUN}@x.test", "password": "wrong"})
check("login rate limiting -> 429", s == 429, (s, r))
s, r = call("PUT", "/auth/password", {"oldPassword": PW, "newPassword": "short"}, E)
check("weak new password refused", s == 422)
s, r = call("GET", f"/documents/employee/{EMP_A}", token=B)
check("company B cannot list A's documents", s == 404, (s, r))
s, r = call("GET", f"/documents/employee/{EMP_A}", token=E)
check("employee can list own documents", s == 200)

print(f"\n{passed} passed, {failed} failed")
if failures:
    print("FAILED:", *failures, sep="\n  - ")
sys.exit(1 if failed else 0)
