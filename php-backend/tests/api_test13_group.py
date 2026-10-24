"""Company group: a holding with three SEPARATE companies under it. Proves the data of the companies can never mix.

Run against a fresh private copy (needs the mysql CLI to mark the group; the API itself cannot create the first group):
    python api_test13_group.py http://127.0.0.1:8098 <path-to-mysql.exe> <port> <database>
"""
import json, subprocess, sys, urllib.request, urllib.error, uuid

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8098") + "/api"
MYSQL = sys.argv[2] if len(sys.argv) > 2 else r"C:\laragon\bin\mysql\mysql-8.4.3-winx64\bin\mysql.exe"
PORT = sys.argv[3] if len(sys.argv) > 3 else "3399"
DB = sys.argv[4] if len(sys.argv) > 4 else "grouptest"
RUN = uuid.uuid4().hex[:6]
PW = "Pass12345!"
ok = fail = 0


def call(method, path, body=None, token=None):
    req = urllib.request.Request(BASE + path, method=method, data=json.dumps(body).encode() if body is not None else None)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        r = urllib.request.urlopen(req)
        return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except Exception:
            return e.code, {}


def check(name, cond, extra=""):
    global ok, fail
    if cond:
        ok += 1; print("  ok  ", name)
    else:
        fail += 1; print("  FAIL", name, extra)


def sql(q):
    subprocess.run([MYSQL, "-h127.0.0.1", f"-P{PORT}", "-uroot", DB, "-e", q], check=True, capture_output=True)


def login(email, password=PW):
    s, r = call("POST", "/auth/login", {"email": email, "password": password})
    return s, r.get("token"), r


def switch(tok, cid):
    return call("POST", "/group/switch", {"companyId": cid}, tok)


def names(r):
    return sorted([x.get("name") or x.get("firstName", "") for x in (r if isinstance(r, list) else r.get("data", []))])


print("== setup: holding company + super admin")
HQ_MAIL = f"ibrahim{RUN}@grp.test"
s, r = call("POST", "/companies/register", {"companyName": f"Al Anad HQ {RUN}", "name": "Ibrahim", "email": HQ_MAIL, "password": PW})
check("holding company created", s == 201, f"{s} {r}")
HQ = r["company"]["id"]; IB_ID = r["user"]["id"]
sql(f"INSERT INTO company_groups (name, slug) VALUES ('Al Anad {RUN}', 'al-anad-{RUN}')")
sql(f"UPDATE companies SET group_id = (SELECT id FROM company_groups WHERE slug = 'al-anad-{RUN}') WHERE id = {HQ}")
sql(f"INSERT INTO group_admins (group_id, user_id) SELECT group_id, {IB_ID} FROM companies WHERE id = {HQ}")
sql(f"INSERT INTO platform_owners (user_id) VALUES ({IB_ID})")      # only the owner creates companies (api_test24 covers the rule itself)
s, ib, r = login(HQ_MAIL)
check("super admin signs in", s == 200 and ib, f"{s}")
g = r.get("group") or {}
check("sign-in answer carries the group + super admin flag", g.get("isSuperAdmin") is True and len(g.get("companies", [])) == 1, f"{g}")

print("== super admin creates three companies, each with its own CEO")
cos = {}
for key in ("one", "two", "three"):
    s, r = call("POST", "/group/companies", {"name": f"Anad {key} {RUN}", "ceoName": f"CEO {key}", "ceoEmail": f"ceo{key}{RUN}@grp.test", "ceoPassword": PW}, ib)
    check(f"company {key} created with CEO", s == 201 and r.get("ceo", {}).get("email") == f"ceo{key}{RUN}@grp.test", f"{s} {r}")
    cos[key] = r["id"]
s, r = call("POST", "/group/companies", {"name": "x", "ceoName": "x", "ceoEmail": f"ceoone{RUN}@grp.test", "ceoPassword": PW}, ib)
check("CEO e-mail must be unique", s == 409, f"{s}")
s, r = call("POST", "/group/companies", {"name": "x", "ceoName": "x", "ceoEmail": f"zz{RUN}@grp.test", "ceoPassword": "short"}, ib)
check("weak CEO password refused", s == 422, f"{s}")
s, r = call("GET", "/group/companies", None, ib)
check("super admin sees 4 companies with counts", s == 200 and len(r.get("companies", [])) == 4 and all("employeeCount" in c for c in r["companies"]), f"{s} {r}")

CEO = {}
for key in cos:
    s, t, r = login(f"ceo{key}{RUN}@grp.test")
    check(f"CEO of {key} signs in", s == 200 and t, f"{s}")
    CEO[key] = t
    gg = r.get("group") or {}
    check(f"CEO of {key} is NOT a super admin and sees only their own company", gg.get("isSuperAdmin") is False and [c["id"] for c in gg.get("companies", [])] == [cos[key]], f"{gg}")
s, r = call("POST", "/group/companies", {"name": "evil", "ceoName": "e", "ceoEmail": f"e{RUN}@grp.test", "ceoPassword": PW}, CEO["one"])
check("a CEO cannot create companies", s == 403, f"{s}")
s, r = call("GET", "/group/access", None, CEO["one"])
check("a CEO cannot read the access list", s == 403, f"{s}")

print("== each company has its own departments and employees")
emp = {}
for key in cos:
    tok = CEO[key]
    s, r = call("POST", "/departments", {"name": f"Dept-{key}-{RUN}"}, tok)
    check(f"{key}: department created", s in (200, 201), f"{s} {r}")
    s, r = call("POST", "/employees", {"first_name": f"Emp{key}", "last_name": "X", "email": f"emp{key}{RUN}@grp.test"}, tok)
    check(f"{key}: employee created", s in (200, 201), f"{s} {r}")
    emp[key] = r
for key in cos:
    s, r = call("GET", "/departments", None, CEO[key])
    seen = [d["name"] for d in (r if isinstance(r, list) else r.get("data", []))]
    check(f"{key}: CEO sees ONLY own departments", seen == [f"Dept-{key}-{RUN}"], f"{seen}")
    s, r = call("GET", "/employees", None, CEO[key])
    lst = r if isinstance(r, list) else r.get("data", [])
    check(f"{key}: CEO sees ONLY own employees", [e["email"] for e in lst] == [f"emp{key}{RUN}@grp.test"], f"{[e.get('email') for e in lst]}")

print("== direct attacks across companies (CEO of one -> data of another)")
other = emp["two"]; other_id = other.get("id")
s, r = call("GET", f"/employees/{other_id}", None, CEO["one"])
check("guessing another company's employee id -> not found", s in (403, 404), f"{s}")
s, r = call("PUT", f"/employees/{other_id}", {"phone": "1"}, CEO["one"])
check("cannot edit another company's employee", s in (403, 404), f"{s}")
s, r = call("DELETE", f"/employees/{other_id}", None, CEO["one"])
check("cannot delete another company's employee", s in (403, 404), f"{s}")
s, r = switch(CEO["one"], cos["two"])
check("a CEO cannot switch into a sibling company", s == 403, f"{s}")
s, r = switch(CEO["one"], HQ)
check("a CEO cannot switch into the holding company", s == 403, f"{s}")
s, r = call("GET", f"/employees?companyId={cos['two']}", None, CEO["one"])
lst = r if isinstance(r, list) else r.get("data", [])
check("a companyId query parameter changes nothing", [e["email"] for e in lst] == [f"empone{RUN}@grp.test"], f"{lst}")

print("== super admin works in one company at a time, nothing mixes")
for key in cos:
    s, r = switch(ib, cos[key])
    check(f"switch into {key}", s == 200 and r.get("company", {}).get("id") == cos[key], f"{s} {r}")
    s, r = call("GET", "/auth/me", None, ib)
    check(f"{key}: /auth/me shows that company and full control", r.get("company", {}).get("id") == cos[key] and r.get("role") == "hr_admin", f"{r.get('role')}")
    s, r = call("GET", "/departments", None, ib)
    seen = [d["name"] for d in (r if isinstance(r, list) else r.get("data", []))]
    check(f"{key}: super admin sees only {key}'s departments", seen == [f"Dept-{key}-{RUN}"], f"{seen}")
    s, r = call("GET", "/employees", None, ib)
    lst = r if isinstance(r, list) else r.get("data", [])
    check(f"{key}: super admin sees only {key}'s employees", [e["email"] for e in lst] == [f"emp{key}{RUN}@grp.test"], f"{[e.get('email') for e in lst]}")
s, r = switch(ib, cos["one"])
s, r = call("GET", f"/employees/{other_id}", None, ib)
check("while in company one, company two's employee id is not reachable", s in (403, 404), f"{s}")
s, r = call("POST", "/departments", {"name": f"Made-by-admin-in-one-{RUN}"}, ib)
s, r = call("GET", "/departments", None, CEO["one"])
check("what the super admin creates lands in the company he is in", f"Made-by-admin-in-one-{RUN}" in [d["name"] for d in (r if isinstance(r, list) else r.get("data", []))], "")
s, r = call("GET", "/departments", None, CEO["two"])
check("...and not in the others", f"Made-by-admin-in-one-{RUN}" not in [d["name"] for d in (r if isinstance(r, list) else r.get("data", []))], "")
s, r = switch(ib, HQ)
s, r = call("GET", "/auth/me", None, ib)
check("super admin can go back home", r.get("company", {}).get("id") == HQ, f"{r.get('company')}")
s, r = switch(ib, 999999)
check("switching into a company that does not exist is refused", s == 403, f"{s}")

print("== an HR employee gets access chosen by the super admin")
s, r = call("POST", "/auth/register", {"name": "Hana HR", "email": f"hana{RUN}@grp.test", "password": PW, "role": "hr_manager"}, CEO["one"])
check("CEO of company one adds an HR user", s == 201, f"{s} {r}")
HANA = r["user"]["id"] if "user" in r else r.get("id")
s, hana, r = login(f"hana{RUN}@grp.test")
check("HR user signs in", s == 200 and hana, f"{s}")
s, r = switch(hana, cos["two"])
check("without a grant: cannot enter company two", s == 403, f"{s}")
s, r = call("GET", "/group/people", None, hana)
check("HR user cannot list the group's people", s == 403, f"{s}")
s, r = call("POST", "/group/access", {"userId": HANA, "companyId": cos["two"], "level": "custom", "modules": ["employees", "dashboard"]}, hana)
check("HR user cannot grant themselves access", s == 403, f"{s}")
s, r = call("POST", "/group/access", {"userId": HANA, "companyId": cos["two"], "level": "custom", "modules": ["employees", "dashboard"]}, ib)
check("super admin grants CUSTOM access (employees only) to company two", s == 201, f"{s} {r}")
s, r = switch(hana, cos["two"])
check("HR user enters company two", s == 200 and r.get("company", {}).get("id") == cos["two"], f"{s} {r}")
s, r = call("GET", "/employees", None, hana)
lst = r if isinstance(r, list) else r.get("data", [])
check("allowed module works and shows only company two's people", [e["email"] for e in lst] == [f"emptwo{RUN}@grp.test"], f"{[e.get('email') for e in lst]}")
for route in ("/payroll", "/departments", "/reports/summary", "/audit", "/hr-staff"):
    s, r = call("GET", route, None, hana)
    check(f"module not granted -> {route} is closed", s == 403, f"{s}")
s, r = call("POST", "/auth/register", {"name": "Evil", "email": f"evil{RUN}@grp.test", "password": PW, "role": "hr_admin"}, hana)
check("a custom grant cannot create admins", s == 403, f"{s}")
s, r = call("POST", "/group/companies", {"name": "x", "ceoName": "x", "ceoEmail": f"q{RUN}@grp.test", "ceoPassword": PW}, hana)
check("a grant never makes someone super admin", s == 403, f"{s}")
s, r = switch(hana, cos["three"])
check("the grant for company two does not open company three", s == 403, f"{s}")
s, r = switch(hana, cos["one"])
check("HR user can go back to their own company", s == 200 and r.get("company", {}).get("id") == cos["one"], f"{s}")

print("== full + read-only grant")
s, r = call("POST", "/group/access", {"userId": HANA, "companyId": cos["three"], "level": "full", "readOnly": True}, ib)
check("grant full but read-only for company three", s == 201, f"{s} {r}")
s, r = switch(hana, cos["three"])
check("HR user enters company three", s == 200, f"{s}")
s, r = call("GET", "/departments", None, hana)
check("read-only: can look", s == 200, f"{s}")
s, r = call("POST", "/departments", {"name": "nope"}, hana)
check("read-only: cannot create", s == 403, f"{s}")
s, r = call("DELETE", f"/employees/{emp['three'].get('id')}", None, hana)
check("read-only: cannot delete", s == 403, f"{s}")

print("== taking access away")
s, r = call("GET", "/group/access", None, ib)
grants = r if isinstance(r, list) else r.get("data", [])
check("access list shows both grants", len(grants) >= 2, f"{grants}")
for gr in grants:
    if gr["userId"] == HANA:
        s, r2 = call("DELETE", f"/group/access/{gr['id']}", None, ib)
        check("revoke access", s == 200, f"{s}")
s, r = call("GET", "/auth/me", None, hana)
check("the revoked person is sent back to their own company at once", r.get("company", {}).get("id") == cos["one"], f"{r.get('company')}")
s, r = call("GET", "/employees", None, hana)
lst = r if isinstance(r, list) else r.get("data", [])
check("...and sees only their own company's data again", [e["email"] for e in lst] == [f"empone{RUN}@grp.test"], f"{[e.get('email') for e in lst]}")

print("== employees never leave their company")
code = emp["one"].get("inviteCode")
s, r = call("POST", "/auth/employee/activate", {"email": f"empone{RUN}@grp.test", "code": code, "password": PW})
check("employee activates", s in (200, 201) and r.get("token"), f"{s} {r}")
etok = r.get("token")
s, r = switch(etok, cos["two"])
check("an employee cannot switch company", s in (401, 403), f"{s}")
s, r = call("GET", "/group", None, etok)
check("an employee cannot use the group area", s == 403, f"{s}")
eid = None
s, r = call("GET", "/auth/me", None, etok)
eid = r.get("id")
s, r = call("POST", "/group/access", {"userId": eid, "companyId": cos["two"], "level": "full"}, ib)
check("access cannot be granted to an employee account", s == 422, f"{s} {r}")

print("== suspend a company")
s, r = call("PUT", f"/group/companies/{cos['two']}", {"status": "suspended"}, ib)
check("super admin suspends company two", s == 200, f"{s} {r}")
s, t, r = login(f"ceotwo{RUN}@grp.test")
check("its CEO can no longer sign in", s == 403, f"{s}")
s, r = switch(ib, cos["two"])
check("nobody can switch into a suspended company", s == 403, f"{s}")
s, r = call("PUT", f"/group/companies/{HQ}", {"status": "suspended"}, ib)
check("the holding company of the super admin cannot be suspended", s == 422, f"{s}")
s, r = call("PUT", f"/group/companies/{cos['two']}", {"status": "active", "name": f"Anad two renamed {RUN}"}, ib)
check("reactivate + rename", s == 200, f"{s}")

print("== a second CEO account")
s, r = call("POST", f"/group/companies/{cos['three']}/ceo", {"name": "New CEO", "email": f"newceo{RUN}@grp.test", "password": PW}, ib)
check("super admin sets a new CEO", s == 201, f"{s} {r}")
s, t, r = login(f"newceo{RUN}@grp.test")
check("new CEO signs in to company three only", s == 200 and (r.get("group") or {}).get("companies", [{}])[0].get("id") == cos["three"], f"{s}")

print(f"\n{ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
