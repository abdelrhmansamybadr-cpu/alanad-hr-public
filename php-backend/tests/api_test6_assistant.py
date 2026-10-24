import json, time, urllib.request

B = "http://127.0.0.1:8099/api"
ok = fail = 0


def call(m, p, b=None, t=None, now=None):
    r = urllib.request.Request(B + p, method=m, data=json.dumps(b).encode() if b is not None else None)
    r.add_header("Content-Type", "application/json")
    if t:
        r.add_header("Authorization", "Bearer " + t)
    if now:
        r.add_header("X-Test-Now", now)
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


def ask(tok, q):
    s, r = call("POST", "/assistant", {"question": q}, tok)
    return s, D(r)


_, r = call("POST", "/auth/login", {"email": "dana@demo.test", "password": "Demo12345!"})
hr = r["token"]
em = f"asst{int(time.time()*1000) % 10**9}@demo.test"
_, e = call("POST", "/employees", {"first_name": "Asma", "last_name": "Helper", "email": em}, hr)
_, r = call("POST", "/auth/employee/activate", {"email": em, "code": e.get("inviteCode") or e.get("invite_code"), "password": "Pass12345!"})
emp = r["token"]

s, a = ask(emp, "How many leave days do I have left?")
check("leave balance (en)", s == 200 and a["intent"] == "leave_balance" and "Leave left" in a["answer"] or "no fixed" in a["answer"], a)
s, a = ask(emp, "كم رصيد إجازاتي؟")
check("leave balance (ar) answers in Arabic", a["intent"] == "leave_balance" and any("؀" <= c <= "ۿ" for c in a["answer"]), a)
s, a = ask(emp, "Did I check in today?")
check("attendance", a["intent"] == "attendance" and "check" in a["answer"].lower(), a)
s, a = ask(emp, "When is the next holiday?")
check("holiday", a["intent"] == "holiday", a)
s, a = ask(emp, "how are my points and level")
check("points", a["intent"] == "points", a)
s, a = ask(emp, "what is my shift")
check("shift", a["intent"] == "shift" and ":" in a["answer"], a)
s, a = ask(emp, "who is my manager")
check("manager", a["intent"] == "manager", a)
s, a = ask(emp, "latest salary payslip")
check("payslip", a["intent"] == "payslip", a)
s, a = ask(emp, "my getting started checklist")
check("onboarding progress", a["intent"] == "onboarding_me" and "of" in a["answer"], a)
s, a = ask(emp, "Who is absent today?")
check("employee cannot ask HR questions", "HR" in a["answer"] or "الموارد" in a["answer"], a)
s, a = ask(emp, "tell me a joke")
check("unknown question gets help", a["intent"] == "help" and len(a["suggestions"]) >= 3, a)
s, r = call("POST", "/assistant", {"question": ""}, emp)
check("empty question rejected", s == 422, s)

s, a = ask(hr, "How many employees do we have?")
check("HR headcount", a["intent"] == "hr_headcount" and "active employees" in a["answer"], a)
s, a = ask(hr, "Who is absent today?")
check("HR absent", a["intent"] == "hr_absent", a)
s, a = ask(hr, "what is waiting for my approval")
check("HR pending", a["intent"] == "hr_pending", a)
s, a = ask(hr, "who is still onboarding")
check("HR onboarding", a["intent"] == "hr_onboarding", a)
s, r = call("GET", "/assistant/suggestions", None, hr)
check("HR suggestions", s == 200 and len(D(r)) == 5, r)
print(f"\n{ok} passed, {fail} failed")
