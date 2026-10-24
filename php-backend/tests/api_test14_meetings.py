"""Online meetings: scheduling rules, invitations, joining, call set-up messages, host controls, company isolation.
Run against a private copy:  python api_test14_meetings.py http://127.0.0.1:8098
"""
import datetime, json, sys, urllib.request, urllib.error, uuid

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8098") + "/api"
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


def iso(delta_min):
    return (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=delta_min)).strftime("%Y-%m-%dT%H:%M:%SZ")


def make_company(tag):
    s, r = call("POST", "/companies/register", {"companyName": f"Meet {tag} {RUN}", "name": f"Admin {tag}", "email": f"admin{tag}{RUN}@meet.test", "password": PW})
    assert s == 201, (s, r)
    return r["token"], r["user"]["id"]


def make_employee(hr_tok, tag):
    em = f"{tag}{RUN}@meet.test"
    s, e = call("POST", "/employees", {"first_name": tag, "last_name": "Emp", "email": em}, hr_tok)
    s, r = call("POST", "/auth/employee/activate", {"email": em, "code": e.get("inviteCode"), "password": PW})
    assert r.get("token"), (s, r)
    return r["token"], r["user"]["id"]


print("== setup: two separate companies")
hr, hr_id = make_company("A")
hrb, hrb_id = make_company("B")
e1, e1_id = make_employee(hr, "ann")
e2, e2_id = make_employee(hr, "bob")
e3, e3_id = make_employee(hr, "cat")          # never invited
eb, eb_id = make_employee(hrb, "eve")          # other company

print("== who may schedule")
s, r = call("GET", "/meetings/bootstrap", None, hr)
inv = [u["id"] for u in r.get("invitable", [])]
check("HR can schedule and may invite everybody in the company", r.get("canSchedule") is True and {e1_id, e2_id, e3_id} <= set(inv) and hr_id not in inv and eb_id not in inv, f"{r}")
s, r = call("GET", "/meetings/bootstrap", None, e1)
check("an employee cannot schedule and has nobody to invite", r.get("canSchedule") is False and r.get("invitable") == [], f"{r}")
s, r = call("POST", "/meetings", {"title": "x", "userIds": [e2_id], "startNow": True}, e1)
check("an employee creating a meeting is refused", s == 403, f"{s}")

print("== creating")
s, r = call("POST", "/meetings", {"title": "No people", "userIds": [], "startNow": True}, hr)
check("a meeting needs at least one invited person", s == 422, f"{s}")
s, r = call("POST", "/meetings", {"title": "", "userIds": [e1_id], "startNow": True}, hr)
check("a title is required", s == 422, f"{s}")
s, r = call("POST", "/meetings", {"title": "No time", "userIds": [e1_id]}, hr)
check("a time is required unless it starts now", s == 422, f"{s}")
s, r = call("POST", "/meetings", {"title": "Bad length", "userIds": [e1_id], "startNow": True, "durationMin": 1}, hr)
check("duration limits are enforced", s == 422, f"{s}")
s, r = call("POST", "/meetings", {"title": "Other company", "userIds": [eb_id], "startNow": True}, hr)
check("a person of ANOTHER company cannot be invited", s == 422, f"{s}")
s, r = call("POST", "/meetings", {"title": "Team sync", "userIds": [e1_id, e2_id], "startNow": True, "notes": "agenda"}, hr)
check("HR starts a meeting now", s == 201 and r.get("canJoin") is True and len(r.get("participants", [])) == 3, f"{s} {r}")
M = r.get("id")
s, r = call("POST", "/meetings", {"title": "Later today", "userIds": [e1_id], "scheduledAt": iso(120)}, hr)
check("HR schedules one for later", s == 201 and r.get("canJoin") is False and r.get("status") == "scheduled", f"{s} {r}")
LATER = r.get("id")
s, r = call("POST", f"/meetings/{LATER}/join", None, e1)
check("nobody can enter a meeting long before its time", s == 422, f"{s}")

print("== who sees what")
s, r = call("GET", "/meetings", None, e1)
ids = [m["id"] for m in (r if isinstance(r, list) else [])]
check("an invited employee sees both meetings", M in ids and LATER in ids, f"{ids}")
s, r = call("GET", "/meetings", None, e2)
ids = [m["id"] for m in (r if isinstance(r, list) else [])]
check("another invited employee sees only theirs", M in ids and LATER not in ids, f"{ids}")
s, r = call("GET", "/meetings", None, e3)
check("a colleague who was not invited sees nothing", (r if isinstance(r, list) else None) == [], f"{r}")
s, r = call("GET", "/meetings?all=1", None, hr)
check("the HR admin can list the whole company", s == 200 and len(r) >= 2, f"{s}")
s, r = call("GET", f"/meetings/{M}", None, e3)
check("an uninvited colleague cannot open the meeting", s == 403, f"{s}")
s, r = call("GET", f"/meetings/{M}", None, hrb)
check("ANOTHER company cannot even see it exists", s == 404, f"{s}")
s, r = call("GET", f"/meetings/{M}/poll", None, hrb)
check("another company cannot poll it", s == 404, f"{s}")
s, r = call("POST", f"/meetings/{M}/signal", {"to": e1_id, "type": "offer", "payload": "{}"}, hrb)
check("another company cannot send messages into it", s == 404, f"{s}")
s, r = call("GET", "/notifications", None, e1)
items = r if isinstance(r, list) else r.get("items", [])
check("the invited employee got a notification", any(n.get("type") == "meeting" for n in items), f"{str(r)[:200]}")

print("== joining and call set-up messages")
s, r = call("POST", f"/meetings/{M}/join", None, e1)
check("employee joins; nobody else is there yet", s == 200 and r.get("present") == [], f"{s} {r}")
s, r = call("POST", f"/meetings/{M}/join", None, hr)
check("the host joins and sees the employee", s == 200 and r.get("present") == [e1_id], f"{s} {r}")
s, r = call("POST", f"/meetings/{M}/join", None, e3)
check("an uninvited colleague cannot join", s == 403, f"{s}")
s, r = call("POST", f"/meetings/{M}/signal", {"to": e1_id, "type": "offer", "payload": json.dumps({"sid": "abc", "d": {"sdp": "v=0", "type": "offer"}})}, hr)
check("host sends an offer to the employee", s == 200 and r.get("id"), f"{s} {r}")
SIG = r.get("id")
s, r = call("GET", f"/meetings/{M}/poll?after=0", None, e1)
sigs = r.get("signals", [])
check("the employee receives it with the sender and payload", len(sigs) == 1 and sigs[0]["from"] == hr_id and sigs[0]["type"] == "offer" and json.loads(sigs[0]["payload"])["sid"] == "abc", f"{r}")
check("poll also tells who is in the call and the status", sorted(r.get("present", [])) == sorted([hr_id, e1_id]) and r.get("status") == "live", f"{r}")
s, r = call("GET", f"/meetings/{M}/poll?after={SIG}", None, e1)
check("asking again from the last id returns nothing new", r.get("signals") == [], f"{r}")
s, r = call("GET", f"/meetings/{M}/poll?after=0", None, hr)
check("a message is delivered only to its receiver", r.get("signals") == [], f"{r}")
s, r = call("POST", f"/meetings/{M}/signal", {"to": e3_id, "type": "offer", "payload": "{}"}, hr)
check("a message to someone who is not in the meeting is refused", s == 422, f"{s}")
s, r = call("POST", f"/meetings/{M}/signal", {"to": e1_id, "type": "Bad Type!", "payload": "{}"}, hr)
check("a malformed message type is refused", s == 422, f"{s}")
s, r = call("POST", f"/meetings/{M}/signal", {"to": e1_id, "type": "offer", "payload": "x" * 200001}, hr)
check("an oversized message is refused", s == 422, f"{s}")
s, r = call("POST", f"/meetings/{M}/signal", {"to": e1_id, "type": "offer", "payload": "{}"}, e2)
check("someone who has not joined the call cannot send messages", s == 422, f"{s}")
s, r = call("POST", f"/meetings/{M}/join", None, e2)
check("the third person joins and sees the two others", s == 200 and sorted(r.get("present", [])) == sorted([hr_id, e1_id]), f"{s} {r}")

print("== a rejoin does not replay old messages")
s, r = call("POST", f"/meetings/{M}/leave", None, e1)
check("employee leaves the call", s == 200, f"{s}")
s, r = call("POST", f"/meetings/{M}/join", None, e1)
check("on rejoin the cursor is past the old offer", s == 200 and r.get("lastSignalId", 0) >= SIG, f"{r}")

print("== host controls")
s, r = call("POST", f"/meetings/{M}/end", None, e1)
check("an employee cannot end the meeting for everybody", s == 403, f"{s}")
s, r = call("DELETE", f"/meetings/{M}/members/{e2_id}", None, e1)
check("an employee cannot remove people", s == 403, f"{s}")
s, r = call("DELETE", f"/meetings/{M}/members/{hr_id}", None, hr)
check("the host cannot be removed", s == 422, f"{s}")
s, r = call("DELETE", f"/meetings/{M}/members/{e2_id}", None, hr)
check("the host removes the third person", s == 200, f"{s}")
s, r = call("GET", f"/meetings/{M}/poll", None, e2)
check("the removed person is told they were removed", s == 200 and r.get("removed") is True, f"{s} {r}")
s, r = call("POST", f"/meetings/{M}/signal", {"to": hr_id, "type": "offer", "payload": "{}"}, e2)
check("the removed person can no longer send messages", s == 403, f"{s}")
s, r = call("POST", f"/meetings/{M}/join", None, e2)
check("the removed person cannot rejoin", s == 403, f"{s}")
s, r = call("PUT", f"/meetings/{LATER}", {"title": "Hacked"}, e1)
check("an employee cannot change a meeting", s == 403, f"{s}")
s, r = call("PUT", f"/meetings/{LATER}", {"title": "Renamed"}, hr)
check("the host renames a meeting", s == 200 and r.get("title") == "Renamed", f"{s} {r}")
s, r = call("DELETE", f"/meetings/{LATER}", None, hr)
check("the host cancels a meeting", s == 200, f"{s}")
s, r = call("GET", f"/meetings/{LATER}", None, e1)
check("it shows as cancelled", r.get("status") == "cancelled", f"{r}")

print("== ending")
s, r = call("POST", f"/meetings/{M}/end", None, hr)
check("the host ends it for everybody", s == 200, f"{s}")
s, r = call("GET", f"/meetings/{M}/poll", None, e1)
check("others see that it ended", r.get("status") == "ended", f"{r}")
s, r = call("POST", f"/meetings/{M}/signal", {"to": e1_id, "type": "offer", "payload": "{}"}, hr)
check("no messages after the end", s == 422, f"{s}")
s, r = call("POST", f"/meetings/{M}/join", None, e1)
check("nobody can join an ended meeting", s == 422, f"{s}")

print("== last person leaving ends a live meeting")
s, r = call("POST", "/meetings", {"title": "Quick chat", "userIds": [e1_id], "startNow": True}, hr)
Q = r["id"]
call("POST", f"/meetings/{Q}/join", None, hr)
call("POST", f"/meetings/{Q}/join", None, e1)
call("POST", f"/meetings/{Q}/leave", None, hr)
s, r = call("GET", f"/meetings/{Q}", None, e1)
check("still live while someone is in", r.get("status") == "live", f"{r}")
call("POST", f"/meetings/{Q}/leave", None, e1)
s, r = call("GET", f"/meetings/{Q}", None, hr)
check("ended when the last person leaves", r.get("status") == "ended", f"{r}")

print("== ringing (incoming meeting alert on every device)")


def ring(tok):
    s, r = call("GET", "/meetings/ring", None, tok)
    return [m["id"] for m in (r if isinstance(r, list) else [])]


s, r = call("POST", "/meetings", {"title": "Ring me", "userIds": [e1_id, e2_id], "startNow": True}, hr)
RING = r["id"]
check("an invited person is rung when the meeting starts", RING in ring(e1) and RING in ring(e2), f"{ring(e1)} {ring(e2)}")
check("the host is not rung for their own meeting", RING not in ring(hr), f"{ring(hr)}")
check("somebody who was not invited is not rung", RING not in ring(e3), f"{ring(e3)}")
check("another company is never rung", RING not in ring(hrb) and RING not in ring(eb), f"{ring(hrb)}")
s, r = call("POST", "/meetings", {"title": "Not yet", "userIds": [e1_id], "scheduledAt": iso(120)}, hr)
check("a meeting that is hours away does not ring yet", r["id"] not in ring(e1), f"{ring(e1)}")
s, r = call("POST", f"/meetings/{RING}/dismiss", None, e2)
check("declining stops the ringing for that person only", s == 200 and RING not in ring(e2) and RING in ring(e1), f"{s}")
s, r = call("POST", f"/meetings/{RING}/dismiss", None, e3)
check("an uninvited person cannot dismiss", s == 403, f"{s}")
call("POST", f"/meetings/{RING}/join", None, e1)
check("joining stops the ringing", RING not in ring(e1), f"{ring(e1)}")
s, r = call("POST", "/meetings", {"title": "Ring then end", "userIds": [e1_id], "startNow": True}, hr)
RING2 = r["id"]
check("a new meeting rings", RING2 in ring(e1), "")
call("POST", f"/meetings/{RING2}/end", None, hr)
check("an ended meeting stops ringing", RING2 not in ring(e1), f"{ring(e1)}")

print(f"\n{ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
