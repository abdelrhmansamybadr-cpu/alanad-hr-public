"""Egyptian leave preset, kudos feeding the points system, wellbeing signals for HR."""
import datetime, json, time, urllib.request

B = "http://127.0.0.1:8099/api"
ok = fail = 0


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


D = lambda r: r if isinstance(r, list) else r.get("data", r)


def check(n, c, x=""):
    global ok, fail
    if c:
        ok += 1
        print("  ok  ", n)
    else:
        fail += 1
        print("  FAIL", n, x)


def person(hr, tag, **extra):
    em = f"{tag}{int(time.time()*1000) % 10**9}@demo.test"
    _, e = call("POST", "/employees", {"first_name": tag, "last_name": "Extra", "email": em, **extra}, hr)
    _, r = call("POST", "/auth/employee/activate", {"email": em, "code": e.get("inviteCode") or e.get("invite_code"), "password": "Pass12345!"})
    return e["id"], r["token"]


def ago(days):
    return (datetime.date.today() - datetime.timedelta(days=days)).isoformat()


_, r = call("POST", "/auth/login", {"email": "dana@demo.test", "password": "Demo12345!"})
hr = r["token"]
year = datetime.date.today().year

# ---- Egyptian leave preset
people = {
    "new": person(hr, "Nada", start_date=ago(90)),                              # 3 months   -> 0
    "half": person(hr, "Hany", start_date=ago(240)),                            # 8 months   -> 15
    "year": person(hr, "Yara", start_date=ago(800)),                            # 2+ years   -> 21
    "ten": person(hr, "Tarek", start_date=ago(365 * 11)),                       # 11 years   -> 30
    "fifty": person(hr, "Fouad", start_date=ago(800), birth_date=ago(365 * 55)),  # age 55     -> 30
}


def annual(eid):
    s, r = call("GET", f"/leaves/balance?employee_id={eid}&year={year}", None, hr)
    return next((b for b in D(r)["balances"] if b["code"] == "annual"), None)


call("PUT", "/company", {"attendancePolicy": {"leavePreset": "egypt"}}, hr)
got = {k: annual(v[0]) for k, v in people.items()}
check("under 6 months: not entitled yet, and 0 left (not unlimited)", got["new"] and got["new"]["total"] == 0 and got["new"]["remaining"] == 0, got["new"])
check("6 to 12 months: 15 days", got["half"]["total"] == 15, got["half"])
check("1 to 10 years: 21 days", got["year"]["total"] == 21, got["year"])
check("10+ years: 30 days", got["ten"]["total"] == 30, got["ten"])
check("age 50+: 30 days", got["fifty"]["total"] == 30, got["fifty"])
tok = people["new"][1]
s, r = call("POST", "/leaves", {"type": "annual", "start_date": ago(-10), "end_date": ago(-10)}, tok)
check("a new hire cannot request annual leave yet", s == 422 and "balance" in json.dumps(r).lower(), (s, r))
call("PUT", "/company", {"attendancePolicy": {"leavePreset": "none"}}, hr)
check("with the preset off, the leave type's own days apply again", annual(people["ten"][0])["total"] != 30 or annual(people["ten"][0])["total"] == annual(people["new"][0])["total"], annual(people["ten"][0]))

# ---- kudos -> green points
call("PUT", "/company", {"pointsConfig": {"enabled": True, "kudosGreenEvery": 3}}, hr)
rid, receiver = person(hr, "Rima")
senders = [person(hr, f"Sender{i}") for i in range(3)]
for i, (sid, stok) in enumerate(senders):
    s, r = call("POST", "/kudos", {"to_employee_id": rid, "message": f"Great work {i}"}, stok)
s, r = call("GET", "/points/me", None, receiver)
hist = D(r).get("history", [])
kudos_points = [h for h in hist if h.get("reason") == "kudos"]
check("the 3rd kudos earns one green point", len(kudos_points) == 1 and kudos_points[0]["color"] == "green", hist)
s, r = call("GET", "/notifications?unread=1&limit=30", None, receiver)
check("and the receiver is told", any(n["type"] == "points" for n in D(r)["items"]), r)
more_id, more = person(hr, "Sender9")
call("POST", "/kudos", {"to_employee_id": rid, "message": "one more"}, more)
s, r = call("GET", "/points/me", None, receiver)
check("the 4th kudos does not earn another", len([h for h in D(r)["history"] if h.get("reason") == "kudos"]) == 1)
call("PUT", "/company", {"pointsConfig": {"kudosGreenEvery": 0}}, hr)
for i in range(3):
    sid, stok = person(hr, f"Late{i}")
    call("POST", "/kudos", {"to_employee_id": rid, "message": "after switching off"}, stok)
s, r = call("GET", "/points/me", None, receiver)
check("with the setting at 0 no more points are given", len([h for h in D(r)["history"] if h.get("reason") == "kudos"]) == 1)
call("PUT", "/company", {"pointsConfig": {"kudosGreenEvery": 5}}, hr)

# ---- wellbeing (HR only)
s, r = call("GET", "/stats/wellbeing", None, hr)
w = D(r)
check("HR gets wellbeing signals", s == 200 and [x["key"] for x in w["signals"]] == ["no_leave", "overtime", "rough_patch"], (s, r))
tenid = people["ten"][0]
no_leave = next(x for x in w["signals"] if x["key"] == "no_leave")["employees"]
check("an employee of 11 years with no leave is listed", any(e["employeeId"] == tenid for e in no_leave), no_leave[:3])
check("a 3-month employee is not listed", not any(e["employeeId"] == people["new"][0] for e in no_leave))
s, r = call("GET", "/stats/wellbeing", None, people["ten"][1])
check("employees cannot see wellbeing signals", s == 403, s)
print(f"\n{ok} passed, {fail} failed")
