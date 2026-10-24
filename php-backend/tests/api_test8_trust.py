"""Fake-location / shared-phone / offline-sync checks and the "why was my day marked like this?" explanation."""
import json, time, urllib.request, datetime
from zoneinfo import ZoneInfo

B = "http://127.0.0.1:8099/api"
ok = fail = 0
DAY = "2026-10-05"          # a Monday
RUN = str(int(time.time()))


def call(m, p, b=None, t=None, now=None):
    r = urllib.request.Request(B + p, method=m, data=json.dumps(b).encode() if b is not None else None)
    r.add_header("Content-Type", "application/json")
    if t:
        r.add_header("Authorization", "Bearer " + t)
    if now:
        r.add_header("X-Test-Now", f"{DAY} {now}")
    try:
        x = urllib.request.urlopen(r)
        return x.status, json.loads(x.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except Exception:
            return e.code, {}


D = lambda r: r if isinstance(r, list) else r.get("data", r)


def check(n, c, x=""):
    global ok, fail
    if c:
        ok += 1
        print("  ok  ", n)
    else:
        fail += 1
        print("  FAIL", n, x)


def person(hr, tag):
    em = f"{tag}{int(time.time()*1000) % 10**9}@demo.test"
    _, e = call("POST", "/employees", {"first_name": tag, "last_name": "Trust", "email": em}, hr)
    _, r = call("POST", "/auth/employee/activate", {"email": em, "code": e.get("inviteCode") or e.get("invite_code"), "password": "Pass12345!"})
    return e["id"], r["token"]


_, r = call("POST", "/auth/login", {"email": "dana@demo.test", "password": "Demo12345!"})
hr = r["token"]
_, comp = call("GET", "/company", None, hr)
tz = ZoneInfo(D(comp).get("timezone") or "UTC")


def ts(hhmm, day=DAY):
    h, m = map(int, hhmm.split(":"))
    y, mo, d = map(int, day.split("-"))
    return int(datetime.datetime(y, mo, d, h, m, tzinfo=tz).timestamp())


# a clean, known setup: 09:00-17:00, no zone rules, default trust policy
call("PUT", "/company", {"attendancePolicy": {"defaultStart": "09:00", "defaultEnd": "17:00", "blockMockLocation": True, "blockSharedDevice": False, "offlineMaxHours": 12}}, hr)
_, rules = call("GET", "/attendance-rules", None, hr)
for x in D(rules):
    call("PUT", f"/attendance-rules/{x['id']}", {"isActive": False}, hr)

a_id, a = person(hr, "Aya")
b_id, b = person(hr, "Badr")
c_id, c = person(hr, "Cara")

# ---- fake location
s, r = call("POST", "/attendance/check-in", {"mock": True, "lat": 30.0, "lng": 31.0}, a, "10:00:00")
check("fake location is refused", s == 422 and "fake" in json.dumps(r).lower(), (s, r))
s, r = call("GET", "/notifications?unread=1&limit=30", None, hr)
check("HR is told about the attempt", any(n["type"] == "security_flag" for n in D(r).get("items", [])), r)

# ---- offline check-in (really 09:40, synced at 10:00) from phone P1
s, r = call("POST", "/attendance/check-in", {"clientTs": ts("09:40"), "deviceId": "PHONE-1-" + RUN + ""}, a, "10:00:00")
rec = D(r)
check("offline check-in is accepted", s == 201, (s, r))
check("it is recorded at the real time, not the sync time", str(rec.get("checkIn", "")).startswith("09:40"), rec.get("checkIn"))
check("it is flagged as an offline sync", "offline_sync" in str(rec.get("securityFlags")), rec)
check("late status is worked out from the real time", rec.get("status") == "late", rec.get("status"))

# ---- another employee on the same phone
s, r = call("POST", "/attendance/check-in", {"deviceId": "PHONE-1-" + RUN + ""}, b, "10:05:00")
check("shared phone is allowed but flagged by default", s == 201 and "shared_device" in str(D(r).get("securityFlags")), (s, r))
call("PUT", "/company", {"attendancePolicy": {"blockSharedDevice": True}}, hr)
s, r = call("POST", "/attendance/check-in", {"deviceId": "PHONE-1-" + RUN + ""}, c, "10:06:00")
check("shared phone is refused when the rule is on", s == 422, (s, r))
s, r = call("POST", "/attendance/check-in", {"deviceId": "PHONE-3-" + RUN + ""}, c, "10:07:00")
check("a different phone is fine", s == 201, (s, r))

# ---- offline limits
s, r = call("POST", "/attendance/check-out", {"clientTs": ts("17:00", "2026-10-04")}, b, "10:30:00")
check("an offline action older than the limit is refused", s == 422, (s, r))
s, r = call("POST", "/attendance/check-out", {"clientTs": ts("23:00")}, b, "10:30:00")
check("a time in the future is refused", s == 422, (s, r))
s, r = call("POST", "/attendance/check-out", {"clientTs": ts("17:02")}, a, "17:30:00")
check("offline check-out is accepted at its real time", s == 200 and str(D(r).get("checkOut", "")).startswith("17:02"), (s, r))

# ---- the explanation
s, r = call("GET", f"/attendance/explain?date={DAY}", None, a, "18:00:00")
ex = D(r)
codes = [x["code"] for x in ex.get("reasons", [])]
check("explain: shift, lateness and result", s == 200 and "shift" in codes and "late_over_grace" in codes and codes[-1] == "result", (s, codes))
check("explain: offline sync is mentioned", "sec_offline_sync" in codes, codes)
check("explain: late day can be disputed", ex.get("canDispute") is True, ex)
late = next(x for x in ex["reasons"] if x["code"] == "late_over_grace")
check("explain: numbers are included", late["params"]["late"] == 40 and late["params"]["grace"] >= 1, late)
s, r = call("GET", "/attendance/explain?date=2026-10-01", None, a, "18:00:00")
check("explain: a past working day with no record counts as absent", D(r)["status"] == "absent" and any(x["code"] == "no_record" for x in D(r)["reasons"]), D(r))
s, r = call("GET", f"/attendance/explain?date={DAY}&employeeId={a_id}", None, hr)
check("HR can explain an employee's day", s == 200 and D(r).get("employeeId") == a_id, (s, r))
s, r = call("GET", f"/attendance/explain?date={DAY}&employeeId={a_id}", None, b)
check("an employee only sees their own explanation", D(r).get("employeeId") == b_id, D(r))
s, r = call("GET", "/attendance/explain?date=nonsense", None, a)
check("bad date rejected", s == 422, s)
call("PUT", "/company", {"attendancePolicy": {"blockSharedDevice": False}}, hr)
print(f"\n{ok} passed, {fail} failed")
