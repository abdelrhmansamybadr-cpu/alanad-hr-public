"""Payroll: insurance, tax (flat / brackets), loans repaid in instalments, printable payslip links."""
import json, time, urllib.request, urllib.parse

B = "http://127.0.0.1:8099"
ok = fail = 0


def call(m, p, b=None, t=None, raw=False):
    r = urllib.request.Request(B + p, method=m, data=json.dumps(b).encode() if b is not None else None)
    r.add_header("Content-Type", "application/json")
    if t:
        r.add_header("Authorization", "Bearer " + t)
    try:
        x = urllib.request.urlopen(r)
        body = x.read()
        return x.status, (body.decode("utf-8") if raw else json.loads(body or b"{}"))
    except urllib.error.HTTPError as e:
        body = e.read()
        try:
            return e.code, (body.decode("utf-8") if raw else json.loads(body or b"{}"))
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


def api(m, p, b=None, t=None):
    return call(m, "/api" + p, b, t)


def person(hr, tag, salary):
    em = f"{tag}{int(time.time()*1000) % 10**9}@demo.test"
    _, e = api("POST", "/employees", {"first_name": tag, "last_name": "Pay", "email": em, "salary": salary}, hr)
    _, r = api("POST", "/auth/employee/activate", {"email": em, "code": e.get("inviteCode") or e.get("invite_code"), "password": "Pass12345!"})
    return e["id"], r["token"]


def lines(preview):
    return {l["key"]: l["amount"] for l in (D(preview).get("breakdown") or {}).get("lines", [])}


_, r = api("POST", "/auth/login", {"email": "dana@demo.test", "password": "Demo12345!"})
hr = r["token"]
eid, emp = person(hr, "Pia", 10000)
oid, other = person(hr, "Omar", 5000)
M = "2031-01"            # far from any real data, so generating payslips does not collide with anything

api("PUT", "/company", {"payrollPolicy": {"useAttendance": False, "insurancePct": 11, "insuranceCap": 8000, "taxMode": "flat", "taxFlatPct": 10, "taxMonthlyExemption": 2000}}, hr)
s, r = api("GET", f"/payroll/preview?employee_id={eid}&month={M}", None, hr)
ln = lines(r)
check("insurance is 11% of the capped salary (8000)", ln.get("insurance") == -880, ln)
check("flat tax is 10% of what is left after insurance and the exemption", ln.get("tax") == -712, ln)
check("net pay = salary - insurance - tax", D(r)["netPay"] == 8408, D(r))
check("total deductions add up", D(r)["deductions"] == 1592, D(r))

api("PUT", "/company", {"payrollPolicy": {"insurancePct": 0, "taxMode": "brackets", "taxMonthlyExemption": 0, "taxBrackets": ["5000|0", "10000|10", "|20"]}}, hr)
s, r = api("GET", f"/payroll/preview?employee_id={eid}&month={M}", None, hr)
check("bracket tax on 10000 = 500", lines(r).get("tax") == -500, lines(r))
api("PUT", "/employees/" + str(eid), {"salary": 20000}, hr)
s, r = api("GET", f"/payroll/preview?employee_id={eid}&month={M}", None, hr)
check("bracket tax on 20000 = 2500", lines(r).get("tax") == -2500, lines(r))
api("PUT", "/employees/" + str(eid), {"salary": 10000}, hr)

# ---- nothing is deducted when the settings are off
api("PUT", "/company", {"payrollPolicy": {"taxMode": "none", "insurancePct": 0}}, hr)
s, r = api("GET", f"/payroll/preview?employee_id={eid}&month={M}", None, hr)
check("no insurance or tax when switched off", "tax" not in lines(r) and "insurance" not in lines(r) and D(r)["netPay"] == 10000, D(r))

# ---- loans
s, r = api("POST", "/payroll/loans", {"employeeId": eid, "title": "Laptop advance", "amount": 2500, "installment": 1000, "startMonth": "2031-01"}, hr)
loan = D(r)
check("HR adds a loan", s == 201 and loan.get("remaining") == 2500, (s, r))
s, r = api("POST", "/payroll/loans", {"employeeId": eid, "title": "x", "amount": 100, "installment": 500}, hr)
check("instalment cannot exceed the amount", s == 422, s)
s, r = api("POST", "/payroll/loans", {"employeeId": eid, "title": "x", "amount": 0, "installment": 0}, hr)
check("amount must be positive", s == 422, s)
s, r = api("POST", "/payroll/loans", {"employeeId": eid, "title": "x", "amount": 100, "installment": 50}, emp)
check("an employee cannot create a loan", s == 403, s)

key = "loan_" + str(loan["id"])
s, r = api("GET", f"/payroll/preview?employee_id={eid}&month=2031-01", None, hr)
check("first month deducts one instalment", lines(r).get(key) == -1000, lines(r))
api("POST", "/payroll/generate", {"month": "2031-01"}, hr)
api("POST", "/payroll/generate", {"month": "2031-01", "recalculate": True}, hr)
s, r = api("GET", f"/payroll/preview?employee_id={eid}&month=2031-02", None, hr)
check("recalculating a month does not double-charge", lines(r).get(key) == -1000, lines(r))
api("POST", "/payroll/generate", {"month": "2031-02"}, hr)
s, r = api("GET", f"/payroll/preview?employee_id={eid}&month=2031-03", None, hr)
check("last instalment is only what is left (500)", lines(r).get(key) == -500, lines(r))
api("POST", "/payroll/generate", {"month": "2031-03"}, hr)
s, r = api("GET", f"/payroll/preview?employee_id={eid}&month=2031-04", None, hr)
check("nothing more is deducted once the loan is repaid", key not in lines(r), lines(r))
s, r = api("GET", f"/payroll/loans?employee_id={eid}", None, hr)
mine = next(x for x in D(r) if x["id"] == loan["id"])
check("loan shows as done with nothing left", mine["status"] == "done" and mine["remaining"] == 0 and mine["paid"] == 2500, mine)

s, r = api("POST", "/payroll/loans", {"employeeId": eid, "title": "Cancelled one", "amount": 900, "installment": 300, "startMonth": "2031-05"}, hr)
cid_ = D(r)["id"]
s, r = api("GET", "/payroll/preview?employee_id=" + str(eid) + "&month=2031-06", None, hr)
check("an active loan is deducted", lines(r).get("loan_" + str(cid_)) == -300, lines(r))
api("PUT", f"/payroll/loans/{cid_}", {"status": "cancelled"}, hr)
s, r = api("GET", "/payroll/preview?employee_id=" + str(eid) + "&month=2031-06", None, hr)
check("a cancelled loan is not deducted", ("loan_" + str(cid_)) not in lines(r), lines(r))

s, r = api("GET", "/payroll/loans", None, emp)
check("employee sees only their own loans", s == 200 and all(x["employeeId"] == eid for x in D(r)) and len(D(r)) >= 1, (s, r))
s, r = api("GET", "/payroll/loans", None, other)
check("another employee sees none of them", s == 200 and not any(x["employeeId"] == eid for x in D(r)), r)

# ---- printable payslip
s, r = api("GET", f"/payroll?employee_id={eid}&month=2031-01", None, hr)
pid = D(r)[0]["id"]
s, r = api("GET", f"/payroll/{pid}/link?lang=en", None, emp)
url = D(r).get("url", "")
check("an employee gets a link to their own payslip", s == 200 and "/payslip-view?t=" in url, (s, r))
path = url.split("://", 1)[1].split("/", 1)[1]
s, html = call("GET", "/" + path, None, None, raw=True)
check("the link opens without a login", s == 200 and "Net pay" in html and "Pia Pay" in html and "Laptop advance" in html, (s, html[:200]))
check("the page has a print button", "window.print()" in html)
s, html_ar = call("GET", "/" + path.replace("lang=en", "lang=ar"), None, None, raw=True)
check("the Arabic version is right-to-left", s == 200 and 'dir="rtl"' in html_ar and "صافي الراتب" in html_ar, html_ar[:120])
s, bad = call("GET", "/" + path.replace("t=", "t=A", 1), None, None, raw=True)
check("a tampered link is refused", s == 403, s)
s, r = api("GET", f"/payroll/{pid}/link", None, other)
check("another employee cannot get the link", s == 403, (s, r))
s, r = api("GET", f"/payroll/{pid}/link", None, hr)
check("HR can get any payslip link", s == 200, s)

# ---- put the demo company back
api("PUT", "/company", {"payrollPolicy": {"useAttendance": True, "insurancePct": 0, "insuranceCap": 0, "taxMode": "none", "taxFlatPct": 0, "taxMonthlyExemption": 0, "taxBrackets": []}}, hr)
print(f"\n{ok} passed, {fail} failed")
