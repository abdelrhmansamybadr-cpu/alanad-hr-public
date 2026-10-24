"""E-mail: test message, invite e-mails, password reset by e-mail for employees AND HR accounts.
Needs the local rig, which captures outgoing mail in <rig>/mail_outbox.jsonl instead of sending it."""
import json, os, re, time, urllib.request

B = "http://127.0.0.1:8099/api"
OUTBOX = os.environ.get("HR_TEST_OUTBOX", r"C:\Users\abdel\AppData\Local\Temp\claude\C--Users-abdel-Desktop-app-mobile-hr\0538aae6-bb20-42df-80ba-63b2116d1d93\scratchpad\mail_outbox.jsonl")
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


def mails():
    if not os.path.exists(OUTBOX):
        return []
    return [json.loads(l) for l in open(OUTBOX, encoding="utf-8") if l.strip()]


def code_for(to, since):
    for m in reversed(mails()[since:]):
        if m["to"] == to:
            f = re.findall(r">(\d{6})<", m["html"])
            return f[0] if f else None
    return None


def login(email, pw):
    return call("POST", "/auth/login", {"email": email, "password": pw})


_, r = login("dana@demo.test", "Demo12345!")
hr = r["token"]
stamp = str(int(time.time()))

# ---- test message
n0 = len(mails())
s, r = call("POST", "/company/test-email", {}, hr)
check("HR can send a test e-mail to themselves", s == 200 and D(r).get("emailed") is True and D(r).get("to") == "dana@demo.test", (s, r))
check("the test e-mail was produced", len(mails()) == n0 + 1)

# ---- invite by e-mail
em = f"mailinv{stamp}@demo.test"
n0 = len(mails())
s, r = call("POST", "/employees", {"first_name": "Mia", "last_name": "Mail", "email": em, "sendEmail": True}, hr)
emp = D(r)
check("creating an employee can e-mail the invite", s == 201 and emp.get("emailed") is True, (s, r))
sent = code_for(em, n0)
check("the e-mailed code is the real invite code", sent is not None and sent == (emp.get("inviteCode") or emp.get("invite_code")), (sent, emp))
html = next(m["html"] for m in reversed(mails()) if m["to"] == em)
check("the e-mail is bilingual and has the app link", "Al Anad HR" in html and "dir=\"rtl\"" in html and "HR-Mobile-App.apk" in html)
s, r = call("POST", "/auth/employee/activate", {"email": em, "code": sent, "password": "FirstPass1!"})
check("the employee activates with the e-mailed code", s in (200, 201) and r.get("token"), (s, r))
eid = emp["id"]
n0 = len(mails())
s, r = call("POST", f"/employees/{eid}/invite", {"sendEmail": True}, hr)
check("HR can e-mail a fresh reset code", s == 200 and D(r).get("emailed") is True and D(r).get("purpose") == "reset", (s, r))
s, r = call("POST", f"/employees/{eid}/invite", {}, hr)
check("without sendEmail nothing is e-mailed", D(r).get("emailed") is None, r)

# ---- employee forgets the password and resets it herself by e-mail
n0 = len(mails())
generic = None
s, r = call("POST", "/auth/employee/forgot-password", {"email": em})
generic = r.get("message")
check("forgot password answers generically", s == 200 and bool(generic), r)
code = code_for(em, n0)
check("a 6-digit code is e-mailed", code is not None and len(code) == 6, code)
s, r = call("POST", "/auth/employee/reset-password", {"email": em, "code": "000000", "newPassword": "NewPass123!"})
check("a wrong code is refused", s == 422, (s, r))
s, r = call("POST", "/auth/employee/reset-password", {"email": em, "code": code, "newPassword": "short"})
check("a weak new password is refused", s == 422, (s, r))
s, r = call("POST", "/auth/employee/reset-password", {"email": em, "code": code, "newPassword": "NewPass123!"})
check("the e-mailed code resets the password", s == 200, (s, r))
check("the new password works", login(em, "NewPass123!")[0] == 200)
check("the old password no longer works", login(em, "FirstPass1!")[0] == 401)
s, r = call("POST", "/auth/employee/reset-password", {"email": em, "code": code, "newPassword": "Another123!"})
check("a code can only be used once", s == 422, (s, r))

# ---- unknown address looks exactly the same and sends nothing
n0 = len(mails())
s, r = call("POST", "/auth/employee/forgot-password", {"email": f"nobody{stamp}@demo.test"})
check("unknown e-mail gets the same answer", s == 200 and r.get("message") == generic, r)
check("and no e-mail is sent", len(mails()) == n0)

# ---- HR account (used to be impossible without database access)
hr_mail = f"hradm{stamp}@demo.test"
s, r = call("POST", "/auth/register", {"name": "Hala Admin", "email": hr_mail, "password": "HrFirst123!", "role": "hr_manager"}, hr)
check("a second HR account exists for the test", s in (200, 201), (s, r))
n0 = len(mails())
call("POST", "/auth/employee/forgot-password", {"email": hr_mail})
hcode = code_for(hr_mail, n0)
check("an HR account gets a reset code by e-mail", hcode is not None, hcode)
s, r = call("POST", "/auth/employee/reset-password", {"email": hr_mail, "code": hcode, "newPassword": "HrSecond123!"})
check("the HR password is reset", s == 200, (s, r))
check("HR can sign in with the new password", login(hr_mail, "HrSecond123!")[0] == 200)

# ---- limits: 3 codes per address per hour
em3 = f"limit{stamp}@demo.test"
call("POST", "/employees", {"first_name": "Lim", "last_name": "It", "email": em3}, hr)
_, e3 = call("GET", "/employees?search=Lim", None, hr)
n0 = len(mails())
for _ in range(5):
    call("POST", "/auth/employee/forgot-password", {"email": hr_mail})
check("at most 3 reset e-mails per address per hour", len([m for m in mails()[n0:] if m["to"] == hr_mail]) <= 2, len(mails()) - n0)
print(f"\n{ok} passed, {fail} failed")
