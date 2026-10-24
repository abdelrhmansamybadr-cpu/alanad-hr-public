import json, urllib.request, time
B = "http://127.0.0.1:8099/api"
ok = fail = 0
def call(m, p, b=None, t=None, now=None):
    r = urllib.request.Request(B + p, method=m, data=json.dumps(b).encode() if b is not None else None)
    r.add_header("Content-Type", "application/json")
    if t: r.add_header("Authorization", "Bearer " + t)
    if now: r.add_header("X-Test-Now", now)
    try:
        x = urllib.request.urlopen(r); return x.status, json.loads(x.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")
def check(n, c, x=""):
    global ok, fail
    if c: ok += 1; print("  ok  ", n)
    else: fail += 1; print("  FAIL", n, x)
D = lambda r: r if isinstance(r, list) else r.get("data", r)
_, r = call("POST", "/auth/login", {"email": "dana@demo.test", "password": "Demo12345!"}); hr = r["token"]
call("PUT", "/company", {"attendancePolicy": {"defaultStart": "09:00", "defaultEnd": "17:00"}}, hr)
_, rules = call("GET", "/attendance-rules", None, hr)
for x in D(rules):
    call("PUT", f"/attendance-rules/{x['id']}", {"isActive": False}, hr)
em = f"rem{int(time.time())}@demo.test"
_, e = call("POST", "/employees", {"first_name": "Rem", "last_name": "Inder", "email": em}, hr)
_, r = call("POST", "/auth/employee/activate", {"email": em, "code": e.get("inviteCode") or e.get("invite_code"), "password": "Pass12345!"}); t = r["token"]
day = "2026-10-05"   # a Monday
def items(now):
    _, r = call("GET", "/notifications?limit=30", None, t, now); return D(r).get("items", [])
check("no reminder before the shift", not [i for i in items(day + " 08:00:00") if i["type"].startswith("reminder")])
check("check-in reminder after the shift starts", any(i["type"] == "reminder_checkin" for i in items(day + " 10:00:00")))
check("sent only once", sum(1 for i in items(day + " 11:00:00") if i["type"] == "reminder_checkin") == 1)
s, r = call("POST", "/attendance/check-in", {}, t, day + " 11:05:00")
check("checked in", s in (200, 201), (s, r))
check("check-out reminder after the shift ends", any(i["type"] == "reminder_checkout" for i in items(day + " 17:30:00")))
check("no reminders on a weekend", not [i for i in items("2026-10-09 10:00:00") if i["type"] == "reminder_checkin" and "2026-10-09" in json.dumps(i.get("data"))])
print(f"\n{ok} passed, {fail} failed")
