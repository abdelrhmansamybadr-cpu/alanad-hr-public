"""Single-company edition lock: the Al Anad app (X-App-Id: alanad) only accepts people of the company with slug "al-anad".
Run against a private copy:  python api_test12_applock.py http://127.0.0.1:8099
Needs a rig where no company has the slug "al-anad" yet (the test creates it; on a second run the slug would be al-anad-2)."""
import json, sys, urllib.request, urllib.error, uuid

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8099") + "/api"
RUN = uuid.uuid4().hex[:6]
ok = fail = 0


def call(method, path, body=None, token=None, app=None):
    req = urllib.request.Request(BASE + path, method=method, data=json.dumps(body).encode() if body is not None else None)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    if app:
        req.add_header("X-App-Id", app)
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


AN, OT = f"anad{RUN}@lock.test", f"other{RUN}@lock.test"
s, a = call("POST", "/companies/register", {"companyName": "Al Anad", "name": "Anad Admin", "email": AN, "password": "Pass12345!"})
s2, o = call("POST", "/companies/register", {"companyName": f"Other Co {RUN}", "name": "Other Admin", "email": OT, "password": "Pass12345!"})
check("both companies created (no app header)", s == 201 and s2 == 201, f"{s} {s2}")
slug = (a.get("company") or {}).get("slug")
check("Al Anad company has slug al-anad", slug == "al-anad", f"slug={slug} (run on a fresh rig)")
a_tok, o_tok = a.get("token"), o.get("token")

print("== Al Anad app (X-App-Id: alanad)")
s, r = call("POST", "/auth/login", {"email": AN, "password": "Pass12345!"}, app="alanad")
check("Al Anad admin can sign in", s == 200 and r.get("token"), f"{s} {r}")
al_tok = r.get("token")
s, r = call("POST", "/auth/login", {"email": OT, "password": "Pass12345!"}, app="alanad")
check("user of another company is refused (403)", s == 403 and not r.get("token"), f"{s} {r}")
s, r = call("GET", "/auth/me", None, o_tok, app="alanad")
check("other company's existing token is refused (403)", s == 403, f"{s}")
s, r = call("GET", "/employees", None, o_tok, app="alanad")
check("other company's token refused on data routes too", s == 403, f"{s}")
s, r = call("GET", "/auth/me", None, al_tok, app="alanad")
check("Al Anad token works", s == 200, f"{s}")
s, r = call("POST", "/companies/register", {"companyName": f"Sneaky {RUN}", "name": "X", "email": f"x{RUN}@lock.test", "password": "Pass12345!"}, app="alanad")
check("creating a company through the app is refused", s == 403, f"{s}")

print("== employee check-email")
call("POST", "/employees", {"first_name": "Eve", "last_name": "Other", "email": f"eve{RUN}@lock.test"}, o_tok)
call("POST", "/employees", {"first_name": "Ann", "last_name": "Anad", "email": f"ann{RUN}@lock.test"}, a_tok)
s, r = call("POST", "/auth/employee/check-email", {"email": f"eve{RUN}@lock.test"}, app="alanad")
check("other company's employee looks 'not_found' in the Al Anad app", r.get("status") == "not_found", f"{r}")
s, r = call("POST", "/auth/employee/check-email", {"email": OT}, app="alanad")
check("other company's HR e-mail looks 'not_found' in the Al Anad app", r.get("status") == "not_found", f"{r}")
s, r = call("POST", "/auth/employee/check-email", {"email": f"ann{RUN}@lock.test"}, app="alanad")
check("Al Anad employee is found", r.get("status") == "needs_activation", f"{r}")
s, r = call("POST", "/auth/employee/check-email", {"email": f"eve{RUN}@lock.test"})
check("same e-mail without the header (normal app) is unaffected", r.get("status") == "needs_activation", f"{r}")

print("== the normal multi-company product is unaffected")
s, r = call("POST", "/auth/login", {"email": OT, "password": "Pass12345!"})
check("other company signs in normally", s == 200 and r.get("token"), f"{s}")
s, r = call("GET", "/auth/me", None, o_tok)
check("other company token works without the header", s == 200, f"{s}")
s, r = call("POST", "/auth/login", {"email": OT, "password": "Pass12345!"}, app="some-unknown-app")
check("unknown app id is not locked", s == 200, f"{s}")

print(f"\n{ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
