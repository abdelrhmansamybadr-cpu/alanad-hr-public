"""Feature arabic_pack: amounts in Arabic words, printable Arabic letters (signed links), Arabic voice commands.
Run:  python api_test22_arabic.py http://127.0.0.1:8098
"""
import datetime, urllib.request, urllib.error
from feat_common import *

ROOT = BASE[:-4]            # without /api


def fetch(url):
    try:
        r = urllib.request.urlopen(urllib.request.Request(url, headers={"Accept": "text/html"}))
        return r.status, r.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")


today = datetime.date.today()
print("== setup")
hr, hr_uid, C = company("ar")
emp_tok, EID, _ = employee(hr, "Samir", salary=12500.50, position="محاسب", start_date="2019-03-01", last_name="Ali")
oth_tok, OID, _ = employee(hr, "Other", salary=5000)

print("== closed until switched on")
s, r = call("GET", "/arabic/words?amount=5", None, emp_tok)
check("closed while off", s == 403 and r.get("code") == "feature_disabled", f"{s} {r}")
s, r = call("POST", "/arabic/voice", {"text": "سجل حضوري"}, emp_tok)
check("voice closed while off", s == 403, f"{s}")
switch(C, arabic_pack=True)

print("== amounts in Arabic words")
cases = [(1250.5, "EGP", "ألف ومائتان وخمسون جنيهاً وخمسون قرشاً فقط لا غير"), (1, "EGP", "جنيه فقط لا غير"), (2, "EGP", "جنيهان فقط لا غير"),
         (5, "EGP", "خمسة جنيهات فقط لا غير"), (100, "EGP", "مائة جنيهاً فقط لا غير"), (2000, "SAR", "ألفان ريالاً فقط لا غير"),
         (11, "SAR", "أحد عشر ريالاً فقط لا غير"), (0.5, "SAR", "خمسون هللة فقط لا غير"), (0, "EGP", "صفر جنيهاً فقط لا غير"),
         (1500000, "EGP", "مليون وخمسمائة ألف جنيهاً فقط لا غير"), (21, "EGP", "واحد وعشرون جنيهاً فقط لا غير")]
for amount, cur, want in cases:
    s, r = call("GET", f"/arabic/words?amount={amount}&currency={cur}", None, emp_tok)
    check(f"{amount} {cur}", s == 200 and r["words"] == want, f"{r.get('words')!r} != {want!r}")
s, r = call("GET", "/arabic/words?amount=abc", None, emp_tok)
check("bad amount refused", s == 422, f"{s}")
s, r = call("GET", "/arabic/words?amount=5&currency=USD", None, emp_tok)
check("only EGP and SAR", s == 422, f"{s}")

print("== printable Arabic letters")
s, r = call("GET", "/arabic/letter-link?type=employment", None, emp_tok)
check("employee gets a link to their own employment letter", s == 200 and "/arabic-view?t=" in r["url"], f"{s} {r}")
url = r["url"].replace("http://localhost", ROOT)
s, html = fetch(ROOT + url[url.index("/arabic-view"):])
check("the page is Arabic, right-to-left, A4 print styles", s == 200 and 'dir="rtl"' in html and "@page" in html and "شهادة إثبات عمل" in html, f"{s} {html[:200]}")
check("it names the person, the job and the company", "Samir Ali" in html and "محاسب" in html and f"Far {RUN}" in html, "")
check("start date in Gregorian and Hijri", "مارس" in html and "هـ" in html, "")
s, r = call("GET", "/arabic/letter-link?type=salary&digits=ar", None, emp_tok)
url = r["url"]
s, html = fetch(ROOT + url[url.index("/arabic-view"):])
check("salary letter carries the amount in words", "شهادة راتب" in html and "اثنا عشر ألف" in html and "خمسمائة جنيهاً" in html, "")
check("Arabic-Indic digits when asked", "١٢" in html, "")
s, r = call("GET", "/arabic/letter-link?type=experience", None, emp_tok)
s, html = fetch(ROOT + r["url"][r["url"].index("/arabic-view"):])
check("experience letter with the length of service", s == 200 and "شهادة خبرة" in html and "سنة" in html, "")
s, r = call("GET", "/arabic/letter-link?type=weird", None, emp_tok)
check("unknown letter type refused", s == 422, f"{s}")
s, r = call("GET", f"/arabic/letter-link?type=salary&employee_id={EID}", None, oth_tok)
check("a colleague cannot ask for someone else's letter (gets their own)", s == 200 and "t=" in r["url"], f"{s}")
s, r1 = call("GET", f"/arabic/letter-link?type=salary&employee_id={EID}", None, hr)
check("HR can issue a letter for any employee", s == 200, f"{s}")
tok = r1["url"].split("t=")[1]
s, html = fetch(f"{ROOT}/arabic-view?t={tok[:-3]}abc")
check("a tampered link is refused", s == 403, f"{s}")
s, html = fetch(f"{ROOT}/arabic-view?t=garbage")
check("garbage is refused", s == 403, f"{s}")
switch(C, arabic_pack=False)
s, html = fetch(f"{ROOT}/arabic-view?t={tok}")
check("a valid link stops working the moment the feature is switched off", s == 403, f"{s}")
switch(C, arabic_pack=True)
s, html = fetch(f"{ROOT}/arabic-view?t={tok}")
check("and works again when it is back on", s == 200 and "شهادة راتب" in html, f"{s}")

print("== Arabic payslip link")
s, r = call("POST", "/payroll/generate", {"month": "2031-05"}, hr)
s, r = call("GET", "/payroll?month=2031-05", None, emp_tok)
rows = r if isinstance(r, list) else r.get("items", r.get("data", []))
PID = rows[0]["id"]
s, r = call("GET", f"/arabic/payslip/{PID}", None, emp_tok)
check("a signed payslip link in Arabic", s == 200 and "lang=ar" in r["url"] and "/payslip-view?t=" in r["url"], f"{s} {r}")
s, html = fetch(ROOT + r["url"][r["url"].index("/payslip-view"):])
check("it opens the payslip page, not the portal", s == 200 and "Al Anad HR</title>" not in html and 'dir="rtl"' in html, f"{s} {html[:150]}")
s, r = call("GET", f"/arabic/payslip/{PID}", None, oth_tok)
check("somebody else's payslip is refused", s in (403, 404), f"{s}")

print("== voice commands")


def say(text, tok=emp_tok):
    s, r = call("POST", "/arabic/voice", {"text": text}, tok)
    assert s == 200, (s, r)
    return r


r = say("سجل حضوري")
check("'سجل حضوري' -> check-in, needs confirmation, nothing done yet", r["intent"] == "check_in" and r["confirm"] is True, f"{r}")
n = sql_out(f"SELECT COUNT(*) FROM attendance WHERE employee_id = {EID}")
check("voice itself changed nothing in attendance", n == "0", f"{n}")
r = say("سجّلي انصرافي")
check("checkout (with diacritics / dialect)", r["intent"] == "check_out" and r["confirm"] is True, f"{r}")
r = say("خلصت شغل")
check("Egyptian: 'خلصت شغل' -> checkout", r["intent"] == "check_out", f"{r}")
r = say("انا وصلت الشغل")
check("Egyptian: 'أنا وصلت الشغل' -> check-in", r["intent"] == "check_in", f"{r}")
r = say("هل سجلت حضوري اليوم؟")
check("a QUESTION about attendance is answered, not executed", r["intent"] == "attendance" and r["confirm"] is False and "حضور" in r["answer"], f"{r}")
r = say("كم رصيد إجازاتي")
check("leave balance answered from my records", r["intent"] == "leave_balance" and r["answer"], f"{r}")
r = say("كام نقطة معايا ونقاطي")
check("points", r["intent"] == "points" and r["answer"], f"{r}")
r = say("افتح قسيمة المرتب")
check("'افتح قسيمة المرتب' -> navigate payslips", r["intent"] == "navigate" and r["target"] == "payslips", f"{r}")
r = say("وديني على الاجتماعات")
check("'وديني على الاجتماعات' -> meetings", r["intent"] == "navigate" and r["target"] == "meetings", f"{r}")
r = say("افتح الاعلانات")
check("announcements", r["target"] == "announcements", f"{r}")
r = say("عايز اجازة")
check("'عايز اجازة' -> opens requests", r["intent"] == "request_leave" and r["target"] == "requests", f"{r}")
r = say("إيه الإجازة الرسمية الجاية؟")
check("holiday question", r["intent"] == "holiday", f"{r}")
r = say("مين الغايبين النهارده")
check("a company question asked by an employee: told it is for HR", r["intent"] == "hr_absent" and "البشرية" in r["answer"], f"{r}")
r = say("كم عدد الموظفين", hr)
check("the same kind of question from HR is answered", r["intent"] == "hr_headcount" and "موظف" in r["answer"], f"{r}")
r = say("blah blah something")
check("gibberish: polite 'did not understand' with examples", r["intent"] == "unknown" and "جرّب" in r["answer"], f"{r}")
r = say("سجل حضوري", hr)
check("an account without an employee record cannot check in by voice", r["confirm"] is False and "غير مرتبط" in r["answer"], f"{r}")
s, r = call("POST", "/arabic/voice", {"text": ""}, emp_tok)
check("empty sentence refused", s == 422, f"{s}")
s, r = call("POST", "/arabic/voice", {"text": "ا" * 400}, emp_tok)
check("very long sentence refused", s == 422, f"{s}")

finish()
