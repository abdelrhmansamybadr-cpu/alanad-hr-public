"""Owner-controlled premium features: who may switch them, and that OFF really means closed.
Run against a private copy:  python api_test15_features.py http://127.0.0.1:8098 <path-to-mysql.exe> <port> <database>
(needs the mysql CLI to mark the owner and the group: the API cannot create owners or groups.)
"""
import json, subprocess, sys, urllib.request, urllib.error, uuid

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8098") + "/api"
MYSQL = sys.argv[2] if len(sys.argv) > 2 else r"C:\laragon\bin\mysql\mysql-8.4.3-winx64\bin\mysql.exe"
PORT = sys.argv[3] if len(sys.argv) > 3 else "3399"
DB = sys.argv[4] if len(sys.argv) > 4 else "grouptest"
RUN = uuid.uuid4().hex[:6]
PW = "Pass12345!"
ok = fail = 0
KEYS = ["local_laws", "arabic_pack", "fair_decisions", "group_dashboard", "manager_coach", "field_proof", "career_path", "complaints"]
CAMEL = {"local_laws": "localLaws", "arabic_pack": "arabicPack", "fair_decisions": "fairDecisions",
         "group_dashboard": "groupDashboard", "manager_coach": "managerCoach", "field_proof": "fieldProof", "career_path": "careerPath", "complaints": "complaints", "approval_chain": "approvalChain"}
# one real route per feature (any request on it is closed while the feature is off)
ROUTE = {"local_laws": "/labor-law/summary", "arabic_pack": "/arabic/payslip", "fair_decisions": "/decisions",
         "group_dashboard": "/portfolio", "manager_coach": "/coach", "field_proof": "/field/visits", "career_path": "/career/me", "complaints": "/complaints"}


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


def company(tag):
    s, r = call("POST", "/companies/register", {"companyName": f"Feat {tag} {RUN}", "name": f"Admin {tag}", "email": f"admin{tag}{RUN}@feat.test", "password": PW})
    assert s == 201, (s, r)
    return r["token"], r["user"]["id"], r["company"]["id"]


def employee(hr, tag):
    em = f"{tag}{RUN}@feat.test"
    s, e = call("POST", "/employees", {"first_name": tag, "last_name": "Emp", "email": em}, hr)
    s, r = call("POST", "/auth/employee/activate", {"email": em, "code": e.get("inviteCode"), "password": PW})
    assert r.get("token"), (s, r)
    return r["token"]


def closed(r):
    return r.get("code") == "feature_disabled"


def gate_status(key, tok):
    """403 feature_disabled = closed. Anything else = the gate let the request through (404 until the handler exists)."""
    s, r = call("GET", ROUTE[key], None, tok)
    return s, r


print("== setup: two companies, an employee, an owner")
a_tok, a_id, A = company("a")
b_tok, b_id, B = company("b")
emp_b = employee(b_tok, "emp")
c_tok, c_id, C = company("c")          # will become the platform owner's home company

print("== nobody can use a feature that was never switched on")
for k in KEYS:
    s, r = gate_status(k, a_tok)
    check(f"{k}: closed by default for company admin", s == 403 and closed(r), f"{s} {r}")
s, r = call("GET", ROUTE["manager_coach"], None, emp_b)
check("closed for employees too", s == 403, f"{s}")

print("== a normal company admin is not an owner")
s, r = call("GET", "/owner/me", None, a_tok)
check("owner/me says no", s == 200 and r.get("canManage") is False and r.get("isOwner") is False, f"{s} {r}")
s, r = call("GET", "/owner/features", None, a_tok)
check("owner panel does not exist for them", s == 404, f"{s}")
s, r = call("PUT", f"/owner/companies/{A}/features", {"flags": {"manager_coach": True}}, a_tok)
check("company admin cannot switch their own features on", s == 404, f"{s}")
s, r = gate_status("manager_coach", a_tok)
check("still closed after that attempt", s == 403 and closed(r), f"{s}")
s, r = call("GET", "/owner/me", None, emp_b)
check("employee cannot even ask", s == 403, f"{s}")

print("== make the owner (server-side only)")
sql(f"INSERT INTO platform_owners (user_id) VALUES ({c_id})")
s, r = call("GET", "/owner/me", None, c_tok)
check("owner/me says owner", s == 200 and r.get("isOwner") is True and r.get("canManage") is True, f"{s} {r}")
s, r = call("GET", "/owner/features", None, c_tok)
check("owner sees the catalogue", s == 200 and len(r.get("features", [])) == len(KEYS) + 1, f"{s} {r}")
cos = {x["id"]: x for x in r.get("companies", [])}
check("owner sees every company with all switches off", A in cos and B in cos and C in cos and not any(cos[A]["flags"].values()), f"{list(cos)[:5]}")

print("== owner switches a feature on for ONE company")
s, r = call("PUT", f"/owner/companies/{B}/features", {"flags": {"managerCoach": True}}, c_tok)
check("switch on accepted", s == 200 and r["flags"]["managerCoach"] is True, f"{s} {r}")
s, r = gate_status("manager_coach", b_tok)
check("company B: gate is open (no longer feature_disabled)", not closed(r) and s != 403, f"{s} {r}")
s, r = gate_status("manager_coach", emp_b)
check("company B employee: gate is open too (the feature's own rules apply)", not closed(r), f"{s} {r}")
s, r = gate_status("manager_coach", a_tok)
check("company A: still closed", s == 403 and closed(r), f"{s} {r}")
s, r = gate_status("career_path", b_tok)
check("company B: other features stay closed", s == 403 and closed(r), f"{s} {r}")
s, r = call("GET", "/company", None, b_tok)
check("apps get the switches in the company settings", s == 200 and r.get("features", {}).get("managerCoach") is True and r["features"].get("careerPath") is False, f"{s} {r.get('features')}")
s, r = call("GET", "/company", None, a_tok)
check("company A settings show it off", r.get("features", {}).get("managerCoach") is False, f"{r.get('features')}")

print("== switching OFF closes it again (for old apps too)")
s, r = call("PUT", f"/owner/companies/{B}/features", {"flags": {"managerCoach": False}}, c_tok)
check("switch off accepted", s == 200 and r["flags"]["managerCoach"] is False, f"{s} {r}")
s, r = gate_status("manager_coach", b_tok)
check("company B: closed again", s == 403 and closed(r), f"{s} {r}")
for m in ("GET", "POST", "PUT", "DELETE"):
    s, r = call(m, ROUTE["manager_coach"], {}, b_tok)
    check(f"{m} refused while off", s == 403 and closed(r), f"{s} {r}")
s, r = call("GET", "/company", None, b_tok)
check("settings show it off again", r.get("features", {}).get("managerCoach") is False, f"{r.get('features')}")

print("== validation and scope")
s, r = call("PUT", f"/owner/companies/{B}/features", {"flags": {"nonsense": True}}, c_tok)
check("unknown feature refused", s == 422, f"{s}")
s, r = call("PUT", f"/owner/companies/{B}/features", {}, c_tok)
check("empty request refused", s == 422, f"{s}")
s, r = call("PUT", "/owner/companies/999999/features", {"flags": {"manager_coach": True}}, c_tok)
check("unknown company refused", s in (403, 404), f"{s}")
s, r = call("POST", "/owner/features/apply", {"key": "career_path", "enabled": True, "companyIds": [A, B]}, c_tok)
check("apply one switch to several companies", s == 200 and r.get("companies") == 2, f"{s} {r}")
s1, r1 = gate_status("career_path", a_tok); s2, r2 = gate_status("career_path", b_tok); s3, r3 = gate_status("career_path", c_tok)
check("A and B open, C untouched", not closed(r1) and not closed(r2) and closed(r3), f"{s1} {s2} {s3}")
s, r = call("POST", "/owner/features/apply", {"key": "career_path", "enabled": False}, c_tok)
check("apply to every company", s == 200 and r.get("companies", 0) >= 3, f"{s} {r}")
s1, r1 = gate_status("career_path", a_tok); s2, r2 = gate_status("career_path", b_tok)
check("closed for all again", closed(r1) and closed(r2), f"{r1} {r2}")

print("== audit log")
s, r = call("GET", "/owner/audit", None, c_tok)
rows = r if isinstance(r, list) else r.get("data", [])
check("every real change is recorded with who did it", s == 200 and len(rows) >= 6 and all(x.get("actorName") for x in rows), f"{s} {len(rows)}")
check("log keeps the feature and the new state", any(x["featureKey"] == "manager_coach" and x["enabled"] in (0, 1, False, True) for x in rows), f"{rows[:2]}")

print("== group Super Admin controls only his own group")
g_tok, g_id, G1 = company("g1")
sql(f"INSERT INTO company_groups (name, slug) VALUES ('Grp {RUN}', 'grp-{RUN}')")
sql(f"UPDATE companies SET group_id = (SELECT id FROM company_groups WHERE slug = 'grp-{RUN}') WHERE id = {G1}")
sql(f"INSERT INTO group_admins (group_id, user_id) SELECT group_id, {g_id} FROM companies WHERE id = {G1}")
sql(f"INSERT INTO platform_owners (user_id) VALUES ({g_id})")      # only the owner creates companies
s, r = call("POST", "/group/companies", {"name": f"Sub {RUN}", "ceoName": "CEO", "ceoEmail": f"ceo{RUN}@feat.test", "ceoPassword": PW}, g_tok)
check("group company created", s == 201, f"{s} {r}")
G2 = r["id"]
sql(f"DELETE FROM platform_owners WHERE user_id = {g_id}")
sql(f"UPDATE companies SET owner_managed = 0 WHERE id = {G2}")
s, r = call("GET", "/owner/me", None, g_tok)
check("Super Admin is recognised (not a platform owner)", r.get("isSuperAdmin") is True and r.get("isOwner") is False and r.get("canManage") is True, f"{r}")
s, r = call("GET", "/owner/features", None, g_tok)
ids = sorted(x["id"] for x in r.get("companies", []))
check("Super Admin sees exactly the companies of his group", ids == sorted([G1, G2]), f"{ids}")
s, r = call("PUT", f"/owner/companies/{G2}/features", {"flags": {"group_dashboard": True, "field_proof": True}}, g_tok)
check("Super Admin switches features for a group company", s == 200 and r["flags"]["groupDashboard"] is True, f"{s} {r}")
s, r = call("PUT", f"/owner/companies/{A}/features", {"flags": {"group_dashboard": True}}, g_tok)
check("but not for a company outside the group", s == 403, f"{s}")
s, r = call("POST", "/owner/features/apply", {"key": "field_proof", "enabled": False}, g_tok)
check("'apply to all' only touches his group", s == 200 and r.get("companies") == 2, f"{s} {r}")
s, r = gate_status("group_dashboard", a_tok)
check("outside company untouched", closed(r), f"{r}")

print(f"\n{ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
