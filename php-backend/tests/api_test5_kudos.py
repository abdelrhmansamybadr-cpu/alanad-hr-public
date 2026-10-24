import json, time, urllib.request

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


def D(r):
    return r if isinstance(r, list) else r.get("data", r)


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
    _, e = call("POST", "/employees", {"first_name": tag, "last_name": "Kudos", "email": em}, hr)
    _, r = call("POST", "/auth/employee/activate", {"email": em, "code": e.get("inviteCode") or e.get("invite_code"), "password": "Pass12345!"})
    return e["id"], r["token"]


_, r = call("POST", "/auth/login", {"email": "dana@demo.test", "password": "Demo12345!"})
hr = r["token"]
a_id, a = person(hr, "Alia")
b_id, b = person(hr, "Bassem")

s, r = call("POST", "/kudos", {"to_employee_id": b_id, "badge": "teamwork", "message": "Thanks for covering my shift!"}, a)
check("employee sends kudos", s == 201 and D(r).get("badge") == "teamwork", (s, r))
kid = D(r).get("id")
s, r = call("POST", "/kudos", {"to_employee_id": a_id, "message": "me"}, a)
check("cannot praise yourself", s == 422, s)
s, r = call("POST", "/kudos", {"to_employee_id": b_id, "message": ""}, a)
check("message is required", s == 422, s)
s, r = call("POST", "/kudos", {"to_employee_id": 999999, "message": "hi"}, a)
check("unknown colleague rejected", s == 422, s)
s, r = call("POST", "/kudos", {"to_employee_id": b_id, "badge": "nonsense", "message": "Nice"}, a)
check("unknown badge falls back to thanks", s == 201 and D(r).get("badge") == "thanks", (s, r))

s, r = call("GET", "/kudos/me", None, b)
check("receiver sees kudos with counts", s == 200 and D(r).get("total") == 2 and D(r)["byBadge"].get("teamwork") == 1, r)
s, r = call("GET", "/notifications?unread=1", None, b)
check("receiver was notified", any(n["type"] == "kudos" for n in D(r).get("items", [])), r)
s, r = call("GET", "/kudos", None, b)
check("feed visible to everyone", s == 200 and len(D(r)) >= 2 and "fromName" in D(r)[0], r)
s, r = call("GET", "/kudos/top", None, b)
top = D(r)
check("top list is sorted by kudos, most first", s == 200 and len(top) >= 1 and top[0]["kudos"] >= 2 and [x["kudos"] for x in top] == sorted((x["kudos"] for x in top), reverse=True), r)

for i in range(3):
    call("POST", "/kudos", {"to_employee_id": b_id, "message": f"extra {i}"}, a)
s, r = call("POST", "/kudos", {"to_employee_id": b_id, "message": "one too many"}, a)
check("daily limit of 5", s == 429, s)

s, r = call("DELETE", f"/kudos/{kid}", None, b)
check("receiver cannot delete", s == 403, s)
s, r = call("DELETE", f"/kudos/{kid}", None, a)
check("author can delete", s == 200, (s, r))
s, r = call("GET", "/kudos", None, hr)
first = D(r)[0]["id"]
s, r = call("DELETE", f"/kudos/{first}", None, hr)
check("HR can delete", s == 200, (s, r))
print(f"\n{ok} passed, {fail} failed")
