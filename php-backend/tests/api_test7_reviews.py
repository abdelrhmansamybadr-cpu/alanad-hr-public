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
    _, e = call("POST", "/employees", {"first_name": tag, "last_name": "Review", "email": em}, hr)
    _, r = call("POST", "/auth/employee/activate", {"email": em, "code": e.get("inviteCode") or e.get("invite_code"), "password": "Pass12345!"})
    return e["id"], r["token"]


_, r = call("POST", "/auth/login", {"email": "dana@demo.test", "password": "Demo12345!"})
hr = r["token"]
a_id, a = person(hr, "Rana")
b_id, b = person(hr, "Rami")
_, hr_me = call("GET", "/auth/me", None, hr)
reviewer = D(hr_me).get("employeeId") or a_id

s, r1 = call("POST", "/reviews", {"employeeId": a_id, "reviewerId": b_id, "period": "2026-Q3", "rating": 4, "feedback": "Great quarter", "status": "submitted"}, hr)
s2, r2 = call("POST", "/reviews", {"employeeId": a_id, "reviewerId": b_id, "period": "2026-Q4", "rating": 3, "feedback": "Draft only", "status": "draft"}, hr)
s3, r3 = call("POST", "/reviews", {"employeeId": b_id, "reviewerId": a_id, "period": "2026-Q3", "rating": 5, "status": "submitted"}, hr)
check("HR creates reviews", s == 201 or s == 200, (s, r1))
published, draft, other = D(r1).get("id"), D(r2).get("id"), D(r3).get("id")

s, r = call("GET", "/reviews", None, a)
ids = [x["id"] for x in D(r)]
check("employee can open the reviews page (no 403)", s == 200, (s, r))
check("employee sees own published review", published in ids, ids)
check("employee does not see own draft", draft not in ids, ids)
check("employee does not see colleague's review", other not in ids, ids)
s, r = call("GET", f"/reviews/{published}", None, a)
check("employee opens own review", s == 200, s)
s, r = call("GET", f"/reviews/{draft}", None, a)
check("employee cannot open own draft", s == 403, s)
s, r = call("GET", f"/reviews/{other}", None, a)
check("employee cannot open a colleague's review", s == 403, s)
s, r = call("POST", "/reviews", {"employeeId": a_id, "reviewerId": a_id, "rating": 5, "status": "submitted"}, a)
check("employee cannot write a review", s == 403, s)
s, r = call("PUT", f"/reviews/{published}", {"rating": 5}, a)
check("employee cannot edit a review", s == 403, s)
s, r = call("DELETE", f"/reviews/{published}", None, a)
check("employee cannot delete a review", s == 403, s)
print(f"\n{ok} passed, {fail} failed")
