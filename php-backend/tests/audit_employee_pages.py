"""Calls every read request the EMPLOYEE app makes, as an ordinary employee, and reports anything that is refused."""
import json, time, urllib.request, datetime

B = "http://127.0.0.1:8099/api"


def call(m, p, b=None, t=None):
    r = urllib.request.Request(B + p, method=m, data=json.dumps(b).encode() if b is not None else None)
    r.add_header("Content-Type", "application/json")
    if t:
        r.add_header("Authorization", "Bearer " + t)
    try:
        x = urllib.request.urlopen(r)
        return x.status, json.loads(x.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except Exception:
            return e.code, {}


_, r = call("POST", "/auth/login", {"email": "dana@demo.test", "password": "Demo12345!"})
hr = r["token"]
em = f"audit{int(time.time()*1000) % 10**9}@demo.test"
_, e = call("POST", "/employees", {"first_name": "Audit", "last_name": "Emp", "email": em}, hr)
eid = e["id"]
_, r = call("POST", "/auth/employee/activate", {"email": em, "code": e.get("inviteCode") or e.get("invite_code"), "password": "Pass12345!"})
t = r["token"]
now = datetime.date.today()

reads = [
    "/auth/me", "/stats/me", "/attendance/today", f"/attendance/summary?month={now.month}&year={now.year}", "/attendance",
    "/leave-types", f"/leaves/balance?year={now.year}", "/leaves", "/requests", "/payroll",
    "/documents/types", f"/documents/employee/{eid}", "/reviews", "/announcements", "/holidays", "/directory",
    "/org", "/company", "/notifications", "/notifications/count", "/points/me", "/points/leaderboard",
    "/points/config", f"/employees/{eid}/promotions", "/employees/me", "/onboarding/me", "/kudos", "/kudos/me",
    "/assistant/suggestions", "/attendance-rules", "/shifts", "/profile",
]
bad = 0
for p in reads:
    s, body = call("GET", p, None, t)
    flag = "ok  " if s == 200 else "FAIL"
    if s != 200:
        bad += 1
    print(f"  {flag} {s} GET {p}" + ("" if s == 200 else f"  -> {body.get('error', body)}"))

# writes an employee legitimately does
for label, m, p, b in [
    ("send a request", "POST", "/requests", {"type": "profile_change", "title": "Fix phone", "payload": {"changes": {"phone": "0100"}}}),
    ("mark notifications read", "POST", "/notifications/read", {"all": True}),
    ("ask the assistant", "POST", "/assistant", {"question": "my points"}),
]:
    s, body = call(m, p, b, t)
    ok = s in (200, 201)
    if not ok:
        bad += 1
    print(f"  {'ok  ' if ok else 'FAIL'} {s} {m} {p}  ({label})" + ("" if ok else f" -> {body.get('error', body)}"))
print(f"\n{bad} problems")
