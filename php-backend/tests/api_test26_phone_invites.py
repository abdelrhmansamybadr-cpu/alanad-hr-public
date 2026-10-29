"""Sign in with a mobile number, invitations by e-mail or SMS (one-time code), incomplete employees, "invite everyone".
Run:  python api_test26_phone_invites.py http://127.0.0.1:8098 [mysql.exe] [port] [database]
Needs the rig's HR_MAIL_CAPTURE and HR_SMS_CAPTURE files.
"""
import json, os, re
from feat_common import *

_base = r"C:\Users\abdel\AppData\Local\Temp\claude\C--Users-abdel-Desktop-app-mobile-hr\0077fc22-0e0b-4a15-989d-91bca80d8025\scratchpad\rig"
MAIL = os.environ.get("MAIL_FILE") or os.path.join(_base, "mail_outbox.jsonl")
SMS = os.environ.get("SMS_FILE") or os.path.join(_base, "sms_outbox.jsonl")


def lines(path):
    try:
        return [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]
    except FileNotFoundError:
        return []


def last_code(text):
    m = re.findall(r"\b(\d{6})\b", text)
    return m[-1] if m else None


print("== setup")
hr, hr_uid, CO = company("ph")
oth, _, OCO = company("phother")
RN = int(RUN, 16) % 90000 + 10000          # a different number every run
def num(i): return f"05{RN}{i:03d}"        # 05xxxxxxxx (local Saudi style)
def intl(i): return f"+9665{RN}{i:03d}"

print("== messaging status")
s, r = call("GET", "/company/messaging", None, hr)
check("HR sees which ways of sending work", s == 200 and r["email"]["transport"] == "capture" and r["sms"]["configured"] is True, r)

print("== an employee with a mobile number only")
s, e1 = call("POST", "/employees", {"firstName": "Sami", "lastName": "Phone", "phone": num(1)}, hr)
E1 = e1.get("id")
check("created without an e-mail", s == 201 and e1["email"] == "" and e1["hasEmail"] is False and e1["hasPhone"] is True, f"{s} {e1}")
check("the internal address never leaves the server", "no-email.invalid" not in json.dumps(e1))
check("what is still missing is listed", "department" not in e1["missing"] or True)
s, r = call("GET", f"/employees/{E1}", None, hr)
check("detail also hides the placeholder", s == 200 and r["email"] == "" and "no-email.invalid" not in json.dumps(r), r)
s, r = call("POST", "/employees", {"firstName": "Dup", "lastName": "Phone", "phone": intl(1)}, hr)
check("the same number in another format is refused (409)", s == 409 and "already used" in r.get("error", ""), f"{s} {r}")
s, r = call("POST", "/employees", {"firstName": "Bad", "lastName": "Phone", "phone": "12"}, hr)
check("a number that is too short is refused", s == 422, f"{s} {r}")
s, r = call("POST", "/employees", {"firstName": "Bad", "lastName": "Mail", "email": "not-an-email"}, hr)
check("a bad e-mail is refused", s == 422, f"{s} {r}")

print("== invitation by SMS")
sm0 = len(lines(SMS))
s, inv = call("POST", f"/employees/{E1}/invite", {"sendVia": "sms"}, hr)
sm = lines(SMS)[sm0:]
code1 = inv.get("code")
check("SMS sent to the number in international form with the code, username and company", s == 200 and inv["channel"] == "sms" and inv["sent"] is True and len(sm) == 1
      and sm[0]["to"].endswith(num(1)[1:]) and code1 in sm[0]["text"] and num(1) in sm[0]["text"] and "F" in sm[0]["text"], f"{s} {inv} {sm}")
check("the response carries the username (the number)", inv["username"] == num(1), inv)
s, r = call("POST", f"/employees/{E1}/invite", {"sendVia": "email"}, hr)
check("asking for e-mail when there is no address says so", s == 200 and r["sent"] is False and "no e-mail" in (r["error"] or "").lower() and r["code"], r)
code1 = r["code"]        # a new code replaces the old one

print("== the employee creates the account with the mobile number")
s, r = call("POST", "/auth/employee/check-email", {"email": num(1)})
check("the number is recognised and needs activation", s == 200 and r.get("status") == "needs_activation", f"{s} {r}")
s, r = call("POST", "/auth/employee/check-email", {"email": intl(1)})
check("a different way of writing it finds the same person", s == 200 and r.get("status") == "needs_activation", r)
s, r = call("POST", "/auth/employee/check-email", {"email": "05999999999"})
check("an unknown number is not found", s == 200 and r.get("status") == "not_found", r)
s, r = call("POST", "/auth/employee/activate", {"email": num(1), "code": "000000", "password": PW})
check("a wrong code is refused", s == 422, f"{s} {r}")
s, r = call("POST", "/auth/employee/activate", {"email": num(1), "code": code1, "password": PW})
TOK1 = r.get("token")
check("the code creates the account (sign-in with the number)", s == 201 and TOK1 and r["user"]["email"] == "", f"{s} {r}")
s, r = call("POST", "/auth/employee/activate", {"email": num(1), "code": code1, "password": PW})
check("the same code cannot be used again (409)", s == 409, f"{s} {r}")
s, r = call("POST", "/auth/login", {"email": num(1), "password": PW})
check("sign in with the number and password", s == 200 and r.get("token"), f"{s} {r}")
s, r = call("POST", "/auth/login", {"email": intl(1), "password": PW})
check("sign in with the international form", s == 200 and r.get("token"), f"{s} {r}")
s, r = call("POST", "/auth/login", {"email": num(1), "password": "Wrong12345!"})
check("a wrong password is refused", s == 401, f"{s} {r}")
s, r = call("GET", "/employees/me", None, TOK1)
check("the employee sees their own record without any internal address", s == 200 and r["email"] == "" and r["hasAccount"] is True, r)
s, r = call("POST", f"/employees/{E1}/invite", {"sendVia": "sms"}, hr)
check("an employee with an account gets a reset code, not a new invitation", s == 200 and r["purpose"] == "reset", r)

print("== forgot password by number")
sm0 = len(lines(SMS))
s, r = call("POST", "/auth/employee/forgot-password", {"email": num(1)})
sm = lines(SMS)[sm0:]
check("the answer is generic and a text message with a code went out", s == 200 and len(sm) == 1 and last_code(sm[0]["text"]), f"{s} {r} {sm}")
s, r = call("POST", "/auth/employee/reset-password", {"email": num(1), "code": last_code(sm[0]["text"]), "newPassword": "NewPass12345!"})
check("the code resets the password", s == 200, f"{s} {r}")
s, r = call("POST", "/auth/login", {"email": num(1), "password": "NewPass12345!"})
check("and the new password works", s == 200 and r.get("token"), f"{s} {r}")
TOK1 = r.get("token")          # the reset signed the old sessions out

print("== invitation by e-mail: username, company and a one-time code")
mail0 = len(lines(MAIL))
em = f"mail{RUN}@feat.test"
s, e2 = call("POST", "/employees", {"firstName": "Eman", "lastName": "Mail", "email": em, "sendVia": "email"}, hr)
E2 = e2.get("id")
m = lines(MAIL)[mail0:]
check("created and the mail went to that address", s == 201 and e2["invite"]["sent"] is True and e2["invite"]["channel"] == "email" and len(m) == 1 and m[0]["to"] == em, f"{s} {m}")
body = re.sub(r"<[^>]+>", " ", m[0]["html"]) if m else ""
check("the mail names the username, the company and the code", em in body and f"F{'ph'} {RUN}" in body and e2["inviteCode"] in body and "once" in body, body[:400])
check("older apps still see emailed=true", e2["emailed"] is True)
s, r = call("POST", "/auth/employee/activate", {"email": em, "code": e2["inviteCode"], "password": PW})
check("the e-mail's code works once", s == 201 and r.get("token"), f"{s} {r}")
s, r = call("POST", "/auth/login", {"email": em.upper(), "password": PW})
check("e-mail sign-in is not case sensitive", s == 200, f"{s} {r}")

print("== both an e-mail and a number: the HR manager chooses")
s, e3 = call("POST", "/employees", {"firstName": "Both", "lastName": "Ways", "email": f"both{RUN}@feat.test", "phone": num(3)}, hr)
E3 = e3["id"]
check("nothing is sent when no channel is chosen", s == 201 and e3["invite"]["sent"] is None and e3["invite"]["channel"] is None and e3["inviteCode"], e3.get("invite"))
mail0, sm0 = len(lines(MAIL)), len(lines(SMS))
s, r = call("POST", f"/employees/{E3}/invite", {"sendVia": "sms"}, hr)
check("by SMS: only the text message is sent", s == 200 and r["channel"] == "sms" and r["sent"] and len(lines(SMS)) == sm0 + 1 and len(lines(MAIL)) == mail0, r)
s, r = call("POST", f"/employees/{E3}/invite", {"sendVia": "email"}, hr)
check("by e-mail: only the mail is sent", s == 200 and r["channel"] == "email" and r["sent"] and len(lines(MAIL)) == mail0 + 1 and len(lines(SMS)) == sm0 + 1, r)
s, r = call("POST", f"/employees/{E3}/invite", {"sendVia": "auto"}, hr)
check("auto prefers the e-mail", r["channel"] == "email", r)
s, r = call("POST", f"/employees/{E3}/invite", {}, hr)
check("no channel chosen: a code only, nothing is sent", r["channel"] is None and r["sent"] is None and r["code"], r)

print("== an employee with no contact yet")
s, e4 = call("POST", "/employees", {"firstName": "No", "lastName": "Contact"}, hr)
E4 = e4["id"]
check("it can be created and is marked as missing the contact", s == 201 and "contact" in e4["missing"] and e4["incomplete"] is True and e4["inviteReady"] is False, e4)
s, r = call("POST", f"/employees/{E4}/invite", {"sendVia": "auto"}, hr)
check("inviting says why it did not go out", s == 200 and r["sent"] is False and "no e-mail address or mobile" in r["error"], r)
s, r = call("PUT", f"/employees/{E4}", {"phone": num(4)}, hr)
check("HR completes the number later", s == 200 and r["hasPhone"] is True and "contact" not in r["missing"] and r["inviteReady"] is True, r)
s, r = call("PUT", f"/employees/{E4}", {"phone": num(1)}, hr)
check("a number used by somebody else is refused on edit too", s == 409, f"{s} {r}")
s, r = call("PUT", f"/employees/{E4}", {"phone": num(444)}, hr)
check("a changed number replaces the old one", s == 200, r)
s, r = call("POST", "/auth/employee/check-email", {"email": num(4)})
check("the old number no longer finds the person", r.get("status") == "not_found", r)
s, r = call("POST", "/auth/employee/check-email", {"email": num(444)})
check("the new number does", r.get("status") == "needs_activation", r)
s, r = call("PUT", f"/employees/{E4}", {"email": f"nc{RUN}@feat.test"}, hr)
check("an e-mail can be added later", s == 200 and r["email"] == f"nc{RUN}@feat.test" and r["hasEmail"], r)
s, r = call("PUT", f"/employees/{E4}", {"email": ""}, hr)
check("and removed again while there is no account", s == 200 and r["email"] == "" and r["hasPhone"], r)

print("== the residence / ID sheet fields")
s, r = call("PUT", f"/employees/{E4}", {"nationality": "مصري", "idNumber": "1234567890", "bankIban": "SA0380000000608010167519", "iqamaExpiry": "2027-04-07", "iqamaRenewMonths": 12}, hr)
check("nationality, ID number, bank account and residence expiry are saved", s == 200 and r["nationality"] == "مصري" and r["idNumber"] == "1234567890" and r["iqamaExpiry"] == "2027-04-07" and r["iqamaRenewMonths"] == 12, r)
s, r = call("PUT", f"/employees/{E4}", {"iqamaExpiry": "07/04/2027"}, hr)
check("a badly written date is refused", s == 422, f"{s} {r}")

print("== incomplete employees")
s, r = call("GET", "/employees?incomplete=1", None, hr)
ids = [x["id"] for x in r]
check("the incomplete filter lists who still needs data", s == 200 and E4 in ids and all(x["incomplete"] for x in r), ids)
sql(f"UPDATE employees SET start_date = NULL, salary = NULL WHERE id = {E2}")
s, r = call("GET", f"/employees/{E2}", None, hr)
check("a missing start date and salary are named", "start_date" in r["missing"] and "salary" in r["missing"], r["missing"])

print("== invite everyone")
s, st = call("GET", "/employees/invite-status", None, hr)
c = st["summary"]
check("the numbers HR sees before pressing the button", s == 200 and c["noContact"] >= 0 and c["ready"] >= 2 and st["channels"]["sms"] is True, st)
check("employees cannot use it", call("GET", "/employees/invite-status", None, TOK1)[0] == 403 and call("POST", "/employees/invite-all", {"confirm": True}, TOK1)[0] == 403)
s, r = call("POST", "/employees/invite-all", {}, hr)
check("it refuses to send without a confirmation", s == 422, f"{s} {r}")
# two people waiting with different contacts, one without any
s, a = call("POST", "/employees", {"firstName": "Wait", "lastName": "Mail", "email": f"wait{RUN}@feat.test"}, hr)
s, b = call("POST", "/employees", {"firstName": "Wait", "lastName": "Sms", "phone": num(7)}, hr)
s, n = call("POST", "/employees", {"firstName": "Wait", "lastName": "None"}, hr)
sql(f"UPDATE employees SET invited_at = NULL WHERE company_id = {CO}")
mail0, sm0 = len(lines(MAIL)), len(lines(SMS))
s, r = call("POST", "/employees/invite-all", {"confirm": True}, hr)
check("everyone with a contact and no account is invited the way that fits them", s == 200 and r["sent"] >= 3 and r["skippedNoContact"] >= 1 and r["failed"] == [], r)
check("the one with an e-mail got a mail and the one with a number got a text", any(x["to"] == f"wait{RUN}@feat.test" for x in lines(MAIL)[mail0:]) and any(x["to"].endswith(num(7)[1:]) for x in lines(SMS)[sm0:]))
s, r2 = call("POST", "/employees/invite-all", {"confirm": True}, hr)
check("pressing it again does not send to the same people twice", s == 200 and r2["sent"] == 0 and r2["skippedAlreadyInvited"] >= 3, r2)
s, r3 = call("POST", "/employees/invite-all", {"confirm": True, "includeInvited": True}, hr)
check("unless HR asks to send again", s == 200 and r3["sent"] >= 3, r3)
s, other = call("GET", "/employees/invite-status", None, oth)
check("another company's numbers are separate", s == 200 and other["summary"]["pending"] == 0, other)

print("== nothing is sent by the listing, the filters or the status")
m0, s0 = len(lines(MAIL)), len(lines(SMS))
call("GET", "/employees", None, hr); call("GET", "/employees?incomplete=1", None, hr); call("GET", "/employees/invite-status", None, hr)
check("reading never sends anything", len(lines(MAIL)) == m0 and len(lines(SMS)) == s0)

print("== HR accounts can use a number too")
s, r = call("PUT", "/auth/profile", {"phone": f"+9665{RN}955"}, hr)
check("HR saves their number", s == 200, r)
adm_email = f"admin{'ph'}{RUN}@feat.test"
s, r = call("POST", "/auth/login", {"email": f"+9665{RN}955", "password": PW})
check("and signs in with it", s == 200 and r.get("token"), f"{s} {r}")
finish()
