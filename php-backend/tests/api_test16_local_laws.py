"""Feature local_laws: Egypt / Saudi law packs drive payroll insurance + tax, leave entitlement, end of service, Hijri dates.
Run:  python api_test16_local_laws.py http://127.0.0.1:8098
"""
from feat_common import *

print("== setup")
hr, hr_uid, C = company("law")
emp_tok, EID, _ = employee(hr, "worker", salary=20000, start_date="2012-01-10", birth_date="1990-05-05")

print("== closed until the owner switches it on")
for path in ("/labor-law/summary", "/labor-law/packs", "/labor-law/hijri"):
    s, r = call("GET", path, None, hr)
    check(f"{path} closed", s == 403 and r.get("code") == "feature_disabled", f"{s} {r}")
s, r = call("GET", f"/payroll/preview?employee_id={EID}&month=2031-03", None, hr)
base_ded = r.get("deductions", r.get("data", {}).get("deductions")) if isinstance(r, dict) else None
check("payroll preview works with the feature off and has no insurance", s == 200 and not any("insurance" in str(l) for l in (r.get("breakdown") or {}).get("lines", [])), f"{s} {r}")

print("== switch on, nothing chosen yet")
switch(C, local_laws=True)
s, r = call("GET", "/labor-law/summary", None, hr)
check("summary answers, not configured", s == 200 and r.get("configured") is False and r.get("hijriToday", {}).get("year", 0) > 1400, f"{s} {r}")
s, r = call("GET", "/labor-law/packs", None, hr)
check("two packs offered", s == 200 and sorted(p["code"] for p in r) == ["EG", "SA"], f"{s} {r}")
s, r = call("PUT", "/labor-law/settings", {"country": "EG"}, emp_tok)
check("employee cannot choose the country", s == 403, f"{s}")
s, r = call("PUT", "/labor-law/settings", {"country": "XX"}, hr)
check("unknown country refused", s == 422, f"{s}")

print("== Egypt pack drives payroll")
s, r = call("PUT", "/labor-law/settings", {"country": "EG"}, hr)
check("Egypt chosen", s == 200 and r.get("configured") is True and r.get("country") == "EG", f"{s} {r}")
s, r = call("GET", f"/payroll/preview?employee_id={EID}&month=2031-03", None, hr)
lines = {l["key"]: l for l in (r.get("breakdown") or {}).get("lines", [])}
ins = abs(lines.get("insurance", {}).get("amount", 0))
check("insurance = 11% of the 16,700 ceiling (1,837)", abs(ins - 1837.0) < 0.01, f"{ins} {lines}")
check("income tax is charged from the Egyptian brackets", abs(lines.get("tax", {}).get("amount", 0)) > 0, f"{lines}")
tax_eg = abs(lines.get("tax", {}).get("amount", 0))

print("== employee sees what the law means for them")
s, r = call("GET", "/labor-law/summary", None, emp_tok)
me = r.get("me", {})
check("annual leave 30 days after 10 years of service", s == 200 and me.get("annualLeaveDays") == 30, f"{me}")
check("insurance + tax estimate shown", abs(me.get("monthlyInsurance", 0) - 1837.0) < 0.01 and me.get("monthlyTax", 0) > 0, f"{me}")
check("probation is over", me.get("probationOver") is True, f"{me}")
s, r = call("GET", f"/labor-law/eos?employee_id={EID}", None, emp_tok)
check("Egypt: no statutory end-of-service (said plainly)", s == 200 and r.get("applicable") is False, f"{s} {r}")

print("== company edits the figures (the ceiling changes every year)")
s, r = call("PUT", "/labor-law/settings", {"country": "EG", "params": {"insurance_cap": 20000}}, hr)
check("edit saved", s == 200 and "insuranceCap" in r.get("edited", []), f"{s} {r}")
s, r = call("GET", f"/payroll/preview?employee_id={EID}&month=2031-03", None, hr)
lines = {l["key"]: l for l in (r.get("breakdown") or {}).get("lines", [])}
check("payroll uses the edited ceiling (2,200)", abs(abs(lines["insurance"]["amount"]) - 2200.0) < 0.01, f"{lines.get('insurance')}")
s, r = call("PUT", "/labor-law/settings", {"country": "EG", "params": {"insurance_pct": 500}}, hr)
check("silly percentage refused", s == 422, f"{s}")
s, r = call("PUT", "/labor-law/settings", {"country": "EG", "params": {"tax_brackets": ["abc"]}}, hr)
check("bad tax step refused", s == 422, f"{s}")

print("== Saudi pack: GOSI, no tax, end of service")
s, r = call("PUT", "/labor-law/settings", {"country": "SA"}, hr)
check("Saudi chosen (edits reset)", s == 200 and r.get("country") == "SA" and r.get("edited") == [], f"{s} {r}")
s, r = call("GET", f"/payroll/preview?employee_id={EID}&month=2031-03", None, hr)
lines = {l["key"]: l for l in (r.get("breakdown") or {}).get("lines", [])}
check("GOSI 10.5% of 20,000 = 2,100", abs(abs(lines["insurance"]["amount"]) - 2100.0) < 0.01, f"{lines.get('insurance')}")
check("no income tax in Saudi", "tax" not in lines, f"{lines}")
s, r = call("GET", f"/labor-law/eos?employee_id={EID}&end_date=2022-01-10&reason=termination", None, hr)
check("end of service: 10 years = 5*0.5 + 5*1 = 7.5 months", s == 200 and abs(r.get("amount", 0) - 150000.0) < 1, f"{s} {r}")
s, r = call("GET", f"/labor-law/eos?employee_id={EID}&end_date=2022-01-10&reason=resignation", None, emp_tok)
check("resignation at exactly 10 years pays in full (employee sees own)", s == 200 and abs(r.get("amount", 0) - 150000.0) < 1, f"{s} {r}")
s, r = call("GET", f"/labor-law/eos?employee_id={EID}&end_date=2015-01-10&reason=resignation", None, hr)
check("resignation after 3 years pays one third of 1.5 months", s == 200 and abs(r.get("amount", 0) - 10000.0) < 1, f"{s} {r}")
other, OID, _ = employee(hr, "other", salary=9000, start_date="2024-06-01")
s, r = call("GET", f"/labor-law/eos?employee_id={EID}", None, other)
check("an employee cannot read someone else's end of service (gets their own)", s == 200 and r.get("years", 0) < 3, f"{s} {r}")
s, r = call("GET", "/labor-law/summary", None, other)
check("Saudi: 21 days under 5 years of service", r.get("me", {}).get("annualLeaveDays") == 21, f"{r.get('me')}")

print("== Hijri")
s, r = call("GET", "/labor-law/hijri?date=2025-03-01", None, emp_tok)
check("1 March 2025 is 1 Ramadan 1446 (+-1 day)", s == 200 and r.get("year") == 1446 and r.get("month") == 9 and r.get("day") in (1, 2, 30), f"{r}")
check("Arabic text present", "رمضان" in r.get("textAr", ""), f"{r}")
s, r = call("GET", "/labor-law/hijri?date=garbage", None, emp_tok)
check("bad date refused", s == 422, f"{s}")

print("== switching the feature off really returns payroll to the manual settings")
switch(C, local_laws=False)
s, r = call("GET", "/labor-law/summary", None, hr)
check("labour-law routes closed again", s == 403 and r.get("code") == "feature_disabled", f"{s}")
s, r = call("GET", f"/payroll/preview?employee_id={EID}&month=2031-03", None, hr)
lines = {l["key"]: l for l in (r.get("breakdown") or {}).get("lines", [])}
check("no insurance or tax any more (company manual settings = none)", "insurance" not in lines and "tax" not in lines, f"{lines}")
switch(C, local_laws=True)
s, r = call("GET", "/labor-law/summary", None, hr)
check("switching back on restores the saved choice", r.get("country") == "SA", f"{r.get('country')}")

finish()
