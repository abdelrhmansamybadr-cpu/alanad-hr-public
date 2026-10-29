"""Leaving certificates (designs, pictures, issue + e-mail + PDF, planned account closing) and contracts (fields, alarms).
Run:  python api_test25_certs_contracts.py http://127.0.0.1:8098 [mysql.exe] [port] [database]
Needs Pillow (to make real test pictures) and the rig's HR_MAIL_CAPTURE file.
"""
import base64, io, json, os, re, datetime
from PIL import Image
from feat_common import *

MAIL = os.environ.get("MAIL_FILE") or r"C:\Users\abdel\AppData\Local\Temp\claude\C--Users-abdel-Desktop-app-mobile-hr\0077fc22-0e0b-4a15-989d-91bca80d8025\scratchpad\rig\mail_outbox.jsonl"
TODAY = datetime.date.today()
iso = lambda d: d.isoformat()


def picture(fmt, w=240, h=170, color=(250, 245, 230)):
    b = io.BytesIO()
    Image.new("RGB" if fmt == "JPEG" else "RGBA", (w, h), color).save(b, fmt)
    return "data:image/%s;base64,%s" % ("jpeg" if fmt == "JPEG" else "png", base64.b64encode(b.getvalue()).decode())


def mails():
    try:
        return [json.loads(l) for l in open(MAIL, encoding="utf-8") if l.strip()]
    except FileNotFoundError:
        return []


def notes(tok, typ):
    s, r = call("GET", "/notifications?limit=100", None, tok)
    return [n for n in (r.get("items") or r.get("data", {}).get("items") or []) if n.get("type") == typ]


def emp_status(eid):
    return sql_out(f"SELECT status FROM employees WHERE id = {eid}")


print("== setup")
hr, hr_uid, CO = company("cert")
sql(f"UPDATE companies SET name = 'Anad Test Co' WHERE id = {CO}")
mgr_tok, MGR, mgr_uid = employee(hr, "Boss")
emp_tok, E1, e1_uid = employee(hr, "Lina", position="Accountant", manager_id=MGR)
_, E2, _ = employee(hr, "Omar")
_, E3, _ = employee(hr, "Sara")
_, E4, _ = employee(hr, "Nabil")

print("== contract fields")
start = TODAY - datetime.timedelta(days=30)
s, r = call("POST", "/employees", {"firstName": "Con", "lastName": "Tract", "email": f"con{RUN}@feat.test", "contractType": "fixed_term", "contractStart": iso(start), "contractMonths": 12}, hr)
CT = r.get("id")
exp_end = (start.replace(year=start.year + 1) - datetime.timedelta(days=1)).isoformat()
check("end date is filled from start + months", s == 201 and r.get("contractEnd") == exp_end and r.get("contractMonths") == 12, f"{s} {r.get('contractEnd')} vs {exp_end}")
s, r = call("PUT", f"/employees/{CT}", {"phone": "010" + str(int(RUN, 16) % 10**7).zfill(7)}, hr)
check("a plain profile edit keeps the contract", s == 200 and r.get("contractEnd") == exp_end and r.get("contractType") == "fixed_term", r)
s, r = call("PUT", f"/employees/{CT}", {"contractEnd": iso(start - datetime.timedelta(days=1))}, hr)
check("a contract cannot end before it starts (422)", s == 422, f"{s} {r}")
s, r = call("PUT", f"/employees/{CT}", {"contractType": "bogus"}, hr)
check("unknown contract type is refused", s == 422, f"{s} {r}")
s, r = call("PUT", f"/employees/{CT}", {"contractStart": "31/12/2026"}, hr)
check("bad date format is refused", s == 422, f"{s} {r}")
s, r = call("PUT", f"/employees/{CT}", {"contractType": "permanent"}, hr)
check("permanent clears the end date", s == 200 and r.get("contractEnd") is None, r)
s, r = call("PUT", f"/employees/{CT}", {"contractType": "probation", "contractStart": iso(TODAY), "contractEnd": iso(TODAY + datetime.timedelta(days=90))}, hr)
check("probation with explicit dates", s == 200 and r.get("contractEnd") == iso(TODAY + datetime.timedelta(days=90)), r)
s, r = call("GET", "/employees/me", None, emp_tok)
check("an employee sees their own contract fields", s == 200 and "contractType" in r, r)

print("== contract alarms")
s, r = call("GET", "/contracts/settings", None, hr)
check("default settings", s == 200 and r.get("remindDays") == [30, 14, 7, 1] and r.get("notifyHr") is True and r.get("notifyEmployee") is False, r)
s, r = call("GET", "/contracts/settings", None, emp_tok)
check("employees cannot read alarm settings", s == 403, s)
s, r = call("PUT", "/contracts/settings", {"remindDays": [60, 30, 7, 7, -2, 9999, 0], "notifyEmployee": True}, hr)
check("settings are cleaned and saved", s == 200 and r.get("remindDays") == [60, 30, 7, 0] and r.get("notifyEmployee") is True, r)
call("PUT", "/contracts/settings", {"remindDays": [30, 14, 7, 1], "notifyEmployee": False, "notifyManager": True}, hr)

# E1 ends in 6 days (stage 7), E2 ended 3 days ago, E3 ends in 200 days (outside every stage), E4 permanent
sql(f"UPDATE employees SET contract_type='fixed_term', contract_start='{iso(TODAY - datetime.timedelta(days=300))}', contract_end='{iso(TODAY + datetime.timedelta(days=6))}' WHERE id = {E1}")
sql(f"UPDATE employees SET contract_type='fixed_term', contract_start='{iso(TODAY - datetime.timedelta(days=300))}', contract_end='{iso(TODAY - datetime.timedelta(days=3))}' WHERE id = {E2}")
sql(f"UPDATE employees SET contract_type='fixed_term', contract_start='{iso(TODAY)}', contract_end='{iso(TODAY + datetime.timedelta(days=200))}' WHERE id = {E3}")
sql(f"UPDATE employees SET contract_type='permanent', contract_end=NULL WHERE id = {E4}")
sql(f"UPDATE contract_settings SET last_run = NULL WHERE company_id = {CO}")
s, r = call("GET", "/contracts/expiring?days=90", None, hr)
ids = [i["id"] for i in r.get("items", [])]
check("expiring list holds the ending + expired, not the far or permanent ones", s == 200 and E1 in ids and E2 in ids and E3 not in ids and E4 not in ids, ids)
check("days left is computed", next(i for i in r["items"] if i["id"] == E1)["daysLeft"] == 6 and next(i for i in r["items"] if i["id"] == E2)["daysLeft"] == -3, r["items"])
check("counts", r["counts"]["expired"] >= 1 and r["counts"]["soon"] >= 1, r["counts"])
hrn = notes(hr, "contract_expiry")
check("HR got one alarm for the ending and one for the expired contract", len(hrn) == 2 and any("ends in 6 days" in n["body"] for n in hrn) and any("ended 3 days ago" in n["body"] for n in hrn), [n["body"] for n in hrn])
call("GET", "/contracts/expiring", None, hr); call("GET", "/notifications", None, hr)
check("no duplicate alarms on the next check", len(notes(hr, "contract_expiry")) == 2)
mn = notes(mgr_tok, "contract_expiry")
check("the direct manager is told about his team member", len(mn) == 1 and "Lina" in mn[0]["body"], mn)
check("the employee is not told (switch is off)", len(notes(emp_tok, "contract_expiry")) == 0)
call("PUT", "/contracts/settings", {"notifyEmployee": True}, hr)
call("GET", "/notifications", None, hr)
sql(f"UPDATE contract_settings SET last_run = NULL WHERE company_id = {CO}"); sql(f"DELETE FROM contract_alerts WHERE company_id = {CO}")
call("GET", "/notifications", None, hr)
en = notes(emp_tok, "contract_expiry")
check("employee gets own-contract wording", len(en) == 1 and en[0]["body"].startswith("Your contract"), en)
s, r = call("POST", f"/contracts/{E1}/renew", {"months": 12}, hr)
exp = (TODAY + datetime.timedelta(days=6)).replace(year=(TODAY + datetime.timedelta(days=6)).year + 1).isoformat()
check("renew extends from the old end date", s == 200 and r.get("contractEnd") == exp, r)
s, r = call("POST", f"/contracts/{E1}/renew", {}, hr)
check("renew needs months or an end date", s == 422, s)
check("employees cannot renew", call("POST", f"/contracts/{E1}/renew", {"months": 1}, emp_tok)[0] == 403)

print("== designs and pictures")
s, r = call("GET", "/certificates/samples", None, hr)
check("four starter designs, layouts are JSON text", s == 200 and len(r) == 4 and all(isinstance(t["layout"], str) and json.loads(t["layout"])["blocks"] for t in r), s)
SAMPLE = r[0]
s, r = call("POST", "/certificates/assets", {"dataUrl": picture("PNG", 600, 400), "name": "bg"}, hr)
BG = r.get("id")
check("a background picture is stored", s == 201 and BG and r["width"] == 600, f"{s} {r}")
s, raw = call("GET", f"/certificates/assets/{BG}", None, hr, raw=True)
check("HR can read it back (PNG bytes)", s == 200 and raw[:4] == b"\x89PNG", s)
check("a plain employee cannot", call("GET", f"/certificates/assets/{BG}", None, emp_tok, raw=True)[0] == 403)
check("a script disguised as a picture is refused", call("POST", "/certificates/assets", {"dataUrl": "data:image/png;base64," + base64.b64encode(b"<?php echo 1;").decode()}, hr)[0] == 422)
check("a huge/odd data URL is refused", call("POST", "/certificates/assets", {"dataUrl": "data:text/html;base64,AAAA"}, hr)[0] == 422)

layout = {"frame": {"style": "double", "color": "#b8975a", "width": 6, "inset": 24},
          "blocks": [{"id": "n", "type": "text", "text": "{name}", "x": 10, "y": 40, "w": 80, "size": 6, "color": "#111111", "align": "center", "bold": True, "font": "serif"},
                     {"id": "logo", "type": "image", "asset": BG, "x": 5, "y": 5, "w": 10, "h": 10}]}
s, r = call("POST", "/certificates/templates", {"name": "Mine", "kind": "experience", "lang": "ar", "width": 1123, "height": 794, "bgColor": "#fffdf8", "bgAssetId": BG, "layout": json.dumps(layout)}, hr)
TPL = r.get("id")
check("a design is saved with its background", s == 201 and TPL and r["bgAssetId"] == BG and r["url"] == f"/certificates/assets/{BG}", f"{s} {r}")
check("layout stays intact (text, keys)", json.loads(r["layout"])["blocks"][0]["text"] == "{name}" and "bold" in json.loads(r["layout"])["blocks"][0], r["layout"][:200])
check("a design that is not JSON is refused", call("POST", "/certificates/templates", {"name": "x", "layout": "nope"}, hr)[0] == 422)
check("a design needs a name", call("POST", "/certificates/templates", {"name": " ", "layout": json.dumps(layout)}, hr)[0] == 422)
bad = dict(layout); bad["blocks"] = [{"type": "image", "asset": 987654, "x": 1, "y": 1, "w": 5, "h": 5}]
check("a design pointing at a picture of nobody is refused", call("POST", "/certificates/templates", {"name": "x", "layout": json.dumps(bad)}, hr)[0] == 422)
s, r = call("PUT", f"/certificates/templates/{TPL}", {"name": "Mine v2", "kind": "end_of_service", "lang": "en", "layout": json.dumps(layout)}, hr)
check("a design can be edited", s == 200 and r["name"] == "Mine v2" and r["kind"] == "end_of_service", r)
s, r = call("GET", "/certificates/templates", None, hr)
check("designs list", s == 200 and any(t["id"] == TPL for t in r), r)
oth, _, OCO = company("other")
check("another company sees none of it", call("GET", f"/certificates/templates/{TPL}", None, oth)[0] == 404 and call("GET", f"/certificates/assets/{BG}", None, oth, raw=True)[0] == 404)
check("employees cannot list designs", call("GET", "/certificates/templates", None, emp_tok)[0] == 403)

print("== issue a certificate")
s, d1 = call("POST", "/certificates/draft", {"employeeId": E1, "templateId": TPL}, hr)
yr = TODAY.year
check("a draft reserves the next number", s == 201 and d1["serial"] == f"CERT-{yr}-0001" and d1["company"] == "Anad Test Co" and d1["employee"]["firstName"] == "Lina", f"{s} {d1}")
s, d2 = call("POST", "/certificates/draft", {"employeeId": E2, "templateId": TPL}, hr)
check("the second draft gets the next number", d2["serial"] == f"CERT-{yr}-0002", d2)
check("a draft for an employee of another company is refused", call("POST", "/certificates/draft", {"employeeId": E1}, oth)[0] == 404)
before = len(mails())
body = {"imageData": picture("PNG", 1123, 794), "title": "Experience certificate", "width": 1123, "height": 794, "values": json.dumps({"name": "Lina Emp"}),
        "sendEmail": True, "leaveDate": iso(TODAY), "close": {"mode": "none"}}
s, r = call("POST", f"/certificates/{d1['id']}/issue", body, hr)
check("issued and e-mailed", s == 201 and r["certificate"]["status"] == "issued" and r["emailed"] is True and r["closure"] is None, f"{s} {r}")
m = mails()[before:]
atts = m[-1].get("attachments", []) if m else []
check("the mail went to the employee with a PDF and a JPG", len(m) == 1 and m[0]["to"] == f"lina{RUN}@feat.test" and sorted(a["name"] for a in atts) == [f"CERT-{yr}-0001.jpg", f"CERT-{yr}-0001.pdf"] and all(a["bytes"] > 500 for a in atts), m[-1:] if m else "no mail")
s, pdf = call("GET", f"/certificates/{d1['id']}/file?type=pdf", None, hr, raw=True)
ok_pdf = s == 200 and pdf[:5] == b"%PDF-" and pdf.rstrip().endswith(b"%%EOF")
if ok_pdf:
    sx = int(re.search(rb"startxref\s+(\d+)", pdf).group(1))
    ok_pdf = pdf[sx:sx + 4] == b"xref"
    offs = re.findall(rb"(\d{10}) 00000 n", pdf)
    ok_pdf = ok_pdf and all(re.match(rb"%d 0 obj" % (i + 1), pdf[int(o):]) for i, o in enumerate(offs))
    ok_pdf = ok_pdf and b"/MediaBox [0 0 842.25 595.50]" in pdf
check("the PDF is well formed (xref offsets, A4-landscape page)", ok_pdf, pdf[:80] if s == 200 else s)
s, jpg = call("GET", f"/certificates/{d1['id']}/file?type=image", None, hr, raw=True)
check("the picture is a JPEG", s == 200 and jpg[:3] == b"\xff\xd8\xff", s)
check("an employee cannot download certificates", call("GET", f"/certificates/{d1['id']}/file", None, emp_tok, raw=True)[0] == 403)
check("another company cannot", call("GET", f"/certificates/{d1['id']}/file", None, oth, raw=True)[0] == 404)
check("issuing twice is refused", call("POST", f"/certificates/{d1['id']}/issue", body, hr)[0] == 409)
check("an issued certificate is kept (cannot delete)", call("DELETE", f"/certificates/{d1['id']}", None, hr)[0] == 409)
s, r = call("GET", "/certificates", None, hr)
check("history lists it (and not the open draft)", s == 200 and [c["serial"] for c in r] == [f"CERT-{yr}-0001"] and r[0]["employeeName"] == "Lina Emp", r)
s, r = call("POST", f"/certificates/{d1['id']}/resend", {"emailTo": "private@feat.test"}, hr)
check("resend to another address", s == 200 and r["emailed"] is True and mails()[-1]["to"] == "private@feat.test", r)
check("a bad address is refused", call("POST", f"/certificates/{d1['id']}/resend", {"emailTo": "nope"}, hr)[0] == 422)
check("no picture = no certificate", call("POST", f"/certificates/{d2['id']}/issue", {"title": "x"}, hr)[0] == 422)
check("a draft can be thrown away", call("DELETE", f"/certificates/{d2['id']}", None, hr)[0] == 200)
sql(f"UPDATE certificates SET created_at = NOW() - INTERVAL 3 DAY WHERE company_id = {CO} AND status = 'draft'")
s, d3 = call("POST", "/certificates/draft", {"employeeId": E3}, hr)
check("a new draft after old unfinished ones does not reuse an issued number", d3["serial"] != f"CERT-{yr}-0001", d3)

print("== planned account closing")
def issue(eid, plan, **kw):
    s, d = call("POST", "/certificates/draft", {"employeeId": eid}, hr)
    return call("POST", f"/certificates/{d['id']}/issue", {"imageData": picture("JPEG"), "title": "End of service", "width": 1123, "height": 794, "sendEmail": kw.get("mail", False), "leaveDate": iso(TODAY), "close": plan}, hr)

s, r = issue(E3, {"mode": "in", "days": 7})
CL = (r.get("closure") or {}).get("id")
check("closing in 7 days is planned, account stays open", s == 201 and CL and r["closure"]["status"] == "pending" and emp_status(E3) == "active", f"{s} {r}")
s, r = call("GET", "/certificates/closures", None, hr)
check("the plan is listed", s == 200 and any(c["id"] == CL and c["employeeName"] == "Sara Emp" for c in r), r)
call("GET", "/notifications", None, hr)
check("not closed before its time", emp_status(E3) == "active")
sql(f"UPDATE exit_closures SET close_at = NOW() - INTERVAL 1 MINUTE WHERE id = {CL}")
call("GET", "/notifications", None, hr)
check("closed when the time comes (employee inactive, login disabled)", emp_status(E3) == "inactive" and sql_out(f"SELECT status FROM users WHERE employee_id = {E3}") == "disabled")
check("HR was told", len(notes(hr, "account_closed")) == 1, notes(hr, "account_closed"))
check("the leaving date was kept", sql_out(f"SELECT termination_date FROM employees WHERE id = {E3}") == iso(TODAY))

s, r = issue(E2, {"mode": "now"})
check("close now: done at once", s == 201 and emp_status(E2) == "inactive", f"{s} {r}")

s, r = issue(E4, {"mode": "date", "date": iso(TODAY + datetime.timedelta(days=10))})
check("close on a date", s == 201 and r["closure"]["closeAt"].startswith(iso(TODAY + datetime.timedelta(days=10)) + " 23:59"), r)
CL4 = r["closure"]["id"]
check("cancel a planned closing", call("DELETE", f"/certificates/closures/{CL4}", None, hr)[0] == 200 and emp_status(E4) == "active")
check("cancelling twice is a 404", call("DELETE", f"/certificates/closures/{CL4}", None, hr)[0] == 404)
s, r = call("POST", "/certificates/closures", {"employeeId": E4, "mode": "in", "days": 2}, hr)
CL4 = r["closure"]["id"]
check("a closing can be planned without a certificate too", s == 201 and r["closure"]["certificateId"] is None, r)
s, r = call("POST", f"/certificates/closures/{CL4}/close-now", None, hr)
check("close-now button", s == 200 and emp_status(E4) == "inactive", f"{s} {r}")
check("a bad date is refused", call("POST", "/certificates/closures", {"employeeId": E1, "mode": "date", "date": "tomorrow"}, hr)[0] == 422)
check("an HR user cannot plan the closing of their own account", call("POST", "/certificates/closures", {"employeeId": 0, "mode": "now"}, hr)[0] == 404)

s, r = issue(E1, {"mode": "none"})
check("with no closing plan HR is reminded to close the account", s == 201 and len(notes(hr, "exit_open")) == 2 and emp_status(E1) == "active", notes(hr, "exit_open"))

print("== sign-in is blocked once the planned time has passed (nobody opened the app in between)")
tok2, E5, _ = employee(hr, "Late")
s, r = issue(E5, {"mode": "in", "days": 1})
sql(f"UPDATE exit_closures SET close_at = NOW() - INTERVAL 1 MINUTE WHERE employee_id = {E5}")
s, r = call("POST", "/auth/login", {"email": f"late{RUN}@feat.test", "password": PW})
check("the employee cannot sign in any more", s == 403 and emp_status(E5) == "inactive", f"{s} {r}")
finish()
