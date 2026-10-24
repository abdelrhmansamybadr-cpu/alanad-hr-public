import json, urllib.request, time

B = "http://127.0.0.1:8099/api"
ok = fail = 0


def call(method, path, body=None, token=None):
    req = urllib.request.Request(B + path, method=method, data=json.dumps(body).encode() if body is not None else None)
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


def D(r):
    return r if isinstance(r, list) else r.get('data', r)


def check(name, cond, extra=""):
    global ok, fail
    if cond:
        ok += 1
        print("  ok  ", name)
    else:
        fail += 1
        print("  FAIL", name, extra)


s, r = call("POST", "/auth/login", {"email": "dana@demo.test", "password": "Demo12345!"})
hr = r.get("token")
check("hr login", bool(hr), r)

s, r = call("GET", "/onboarding/templates", token=hr)
check("templates seeded", s == 200 and len(D(r)) >= 5, r)

email = f"ob{int(time.time())}@demo.test"
s, r = call("POST", "/employees", {"first_name": "Ola", "last_name": "Test", "email": email, "position": "Tester"}, token=hr)
d = D(r)
eid = d.get("id")
code = d.get("inviteCode") or d.get("invite_code")
check("employee created", s == 201 and eid, r)

s, r = call("GET", f"/onboarding/employee/{eid}", token=hr)
v = D(r)
check("checklist auto-created", s == 200 and v.get("total", 0) >= 5, r)
tid_hr = next((t["id"] for t in v.get("tasks", []) if t.get("owner") == "hr"), None)
tid_emp = next((t["id"] for t in v.get("tasks", []) if t.get("owner") == "employee"), None)

s, r = call("POST", "/auth/employee/activate", {"email": email, "code": code, "password": "Pass12345!"})
tok = r.get("token") if isinstance(r, dict) else None
check("employee activated", bool(tok), r)

s, r = call("GET", "/onboarding/me", token=tok)
check("employee sees own checklist", s == 200 and D(r).get("total", 0) >= 5, r)
s, r = call("POST", f"/onboarding/employee/{eid}/tasks", {"title": "Bring a photo", "owner": "employee"}, token=hr)
tid_emp = D(r).get("id") if isinstance(D(r), dict) else None
if not tid_emp:
    s, r = call("GET", f"/onboarding/employee/{eid}", token=hr)
    tid_emp = next(t["id"] for t in D(r)["tasks"] if t["title"] == "Bring a photo")
s, r = call("PUT", f"/onboarding/tasks/{tid_emp}", {"done": True}, token=tok)
check("employee ticks own task", s == 200 and D(r).get("done") == 1, r)
s, r = call("PUT", f"/onboarding/tasks/{tid_hr}", {"done": True}, token=tok)
check("employee cannot tick HR task", s == 403, (s, r))
s, r = call("GET", "/onboarding/overview", token=tok)
check("employee cannot see overview", s == 403, s)
s, r = call("GET", "/onboarding/overview", token=hr)
check("hr overview lists new hire", s == 200 and any(x.get("employeeId") == eid or x.get("employee_id") == eid for x in D(r)), r)
s, r = call("POST", f"/onboarding/employee/{eid}/tasks", {"title": "Sign NDA", "owner": "employee"}, token=hr)
check("hr adds task", s == 201, r)
s, r = call("POST", "/onboarding/templates", {"title": "Bring photos", "owner": "employee", "due_days": 3}, token=hr)
check("template added", s == 201, r)
s, r = call("PUT", f"/onboarding/tasks/{tid_hr}", {"done": True}, token=hr)
check("hr ticks HR task", s == 200, r)
# ---- editing, overdue, start-all
s, r = call("PUT", f"/onboarding/tasks/{tid_emp}", {"title": "Sign the contract", "dueDate": "2020-01-01", "owner": "hr", "description": "Bring ID"}, token=hr)
t = next((x for x in D(r).get("tasks", []) if x["id"] == tid_emp), {})
check("HR edits title, owner, due date, note", s == 200 and t.get("title") == "Sign the contract" and t.get("owner") == "hr" and t.get("dueDate") == "2020-01-01" and t.get("description") == "Bring ID", (s, t))
check("editing does not change done state", t.get("done") in (1, True), t)
s, r = call("PUT", f"/onboarding/tasks/{tid_emp}", {"title": ""}, token=hr)
check("empty title rejected", s == 422, s)
s, r = call("PUT", f"/onboarding/tasks/{tid_emp}", {"dueDate": "31/12/2020"}, token=hr)
check("bad date rejected", s == 422, s)
s, r = call("PUT", f"/onboarding/tasks/{tid_emp}", {"title": "hack"}, token=tok)
check("employee cannot edit tasks", s == 403, s)
s, r = call("PUT", f"/onboarding/tasks/{tid_emp}", {"done": False}, token=hr)
s, r = call("GET", "/onboarding/overview", token=hr)
mine = next((x for x in D(r) if x.get("employeeId") == eid), {})
check("overview counts overdue steps", int(mine.get("overdue", 0)) >= 1, mine)
em2 = f"old{int(time.time())}@demo.test"
call("POST", "/employees", {"first_name": "Old", "last_name": "Timer", "email": em2}, token=hr)
s, r = call("POST", "/onboarding/start-all", {}, token=hr)
check("start-all runs", s == 200 and "started" in D(r), (s, r))
s, r = call("POST", "/onboarding/start-all", {}, token=tok)
check("employee cannot start-all", s == 403, s)

# ---- steps the SYSTEM completes (employee can't tick them; the real action ticks them)
s, r = call("GET", "/onboarding/me", token=tok)
tasks = D(r)["tasks"]
byk = {t.get("autoKey"): t for t in tasks if t.get("autoKey")}
check("system steps carry an autoKey", {"contract", "details", "documents", "team", "policies", "checkin"} <= set(byk), list(byk))
s, r = call("PUT", f"/onboarding/tasks/{byk['contract']['id']}", {"done": True}, token=tok)
check("employee cannot tick a system step", s == 403, (s, r))
check("system step starts open", int(byk["contract"]["done"]) == 0)
s, r = call("POST", "/onboarding/event", {"key": "bogus"}, token=tok)
check("unknown event rejected", s == 422, s)
s, r = call("POST", "/onboarding/event", {"key": "contract"}, token=hr)
check("hr account has no employee record for events", s in (404, 403), s)
for k in ("contract", "details", "policies", "team"):
    s, r = call("POST", "/onboarding/event", {"key": k}, token=tok)
    t = next((x for x in D(r)["tasks"] if x.get("autoKey") == k), {})
    check(f"event '{k}' completes its step by the system", s == 200 and int(t.get("done", 0)) == 1 and t.get("doneByName") == "System", (s, t))
s, r = call("POST", "/onboarding/event", {"key": "contract"}, token=tok)
check("repeating an event is harmless", s == 200, s)
t = next(x for x in D(r)["tasks"] if x.get("autoKey") == "documents")
check("documents step stays open without uploads", int(t["done"]) == 0, t)
t = next(x for x in D(r)["tasks"] if x.get("autoKey") == "checkin")
check("check-in step stays open before any check-in", int(t["done"]) == 0, t)

print(f"\n{ok} passed, {fail} failed")
