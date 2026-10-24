"""
Tests for the automatic attendance policy, location/Wi-Fi zones, reward points, requests that change data,
promotions, department heads, payroll-from-attendance, reports and audit.
Run against a private copy:  python api_test2.py http://127.0.0.1:8099
"""
import json, sys, urllib.request, urllib.error, uuid, datetime

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8099") + "/api"
RUN = uuid.uuid4().hex[:6]
passed = failed = 0
failures = []

_d = datetime.date.today() + datetime.timedelta(days=30)
while _d.weekday() != 0:
    _d += datetime.timedelta(days=1)
MONDAY = _d


def at(h, m=0, day=0):
    return (MONDAY + datetime.timedelta(days=day)).strftime('%Y-%m-%d') + f' {h:02d}:{m:02d}:00'


def dstr(day=0):
    return (MONDAY + datetime.timedelta(days=day)).strftime('%Y-%m-%d')


def call(method, path, body=None, token=None, now=None, raw=False):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    if now:
        req.add_header("X-Test-Now", now)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            txt = r.read().decode("utf-8")
            if raw:
                return r.status, txt
            return r.status, (json.loads(txt) if txt else None)
    except urllib.error.HTTPError as e:
        txt = e.read().decode("utf-8")
        try:
            return e.code, json.loads(txt)
        except Exception:
            return e.code, txt


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  ok   {name}")
    else:
        failed += 1
        failures.append(name)
        print(f"  FAIL {name}  {str(extra)[:400]}")


def section(t):
    print(f"\n== {t}")


PW = "Passw0rd!x"
section("Setup")
s, r = call("POST", "/companies/register", {"companyName": f"Policy Co {RUN}", "name": "Pat Admin", "email": f"pat{RUN}@pol.test", "password": PW})
A = r["token"]
check("company registered", s == 201, (s, r))
s, dept = call("POST", "/departments", {"name": "Ops"}, A)
DEP = dept["id"]


def new_employee(first, extra=None):
    body = {"firstName": first, "lastName": "Tester", "email": f"{first.lower()}{RUN}@pol.test", "position": "Clerk", "salary": 3000, "departmentId": DEP, "startDate": "2025-01-01"}
    body.update(extra or {})
    s, e = call("POST", "/employees", body, A)
    assert s == 201, (s, e)
    s, act = call("POST", "/auth/employee/activate", {"email": body["email"], "code": e["inviteCode"], "password": PW})
    assert s in (200, 201), (s, act)
    return e["id"], act["token"]


E1, T1 = new_employee("Ann")
E2, T2 = new_employee("Bob")
E3, T3 = new_employee("Cid")
E4, T4 = new_employee("Dee")
# keep the test clock in a fresh week
call("GET", "/points/me", token=T1, now=at(8, 0))
for t in (T2, T3, T4):
    call("GET", "/points/me", token=t, now=at(8, 0))

# ---------------------------------------------------------------- automatic status
section("Status is decided by the server")
s, r = call("POST", "/attendance/check-in", {"status": "present"}, T2, now=at(9, 10))
check("on time within grace -> present (client status ignored)", s == 201 and r["status"] == "present", (s, r))
s, r = call("POST", "/attendance/check-in", {"status": "present"}, T3, now=at(9, 40))
check("40 min after start -> late", s == 201 and r["status"] == "late" and r["lateMinutes"] == 40, (s, r))
s, r = call("POST", "/attendance/check-in", {"status": "present"}, T4, now=at(11, 30))
check("2.5 h after start -> half_day", s == 201 and r["status"] == "half_day", (s, r))
s, r = call("POST", "/attendance", {"employeeId": E1, "date": dstr(), "status": "present", "checkIn": "09:00"}, T1, now=at(12))
check("employee cannot create attendance", s == 403, (s, r))
s, r = call("PUT", f"/attendance/{r.get('id', 1) if isinstance(r, dict) else 1}", {"status": "present"}, T3)
check("employee cannot edit attendance", s == 403, (s, r))
s, r = call("POST", "/attendance/check-out", {}, T2, now=at(14, 0))
check("leaving 3 h early -> half_day", s == 200 and r["status"] == "half_day" and r["earlyLeaveMinutes"] == 180, (s, r))
s, r = call("POST", "/attendance/check-out", {}, T3, now=at(17, 30))
check("late employee who stays -> stays late, overtime counted", s == 200 and r["status"] == "late" and r["overtimeMinutes"] == 30, (s, r))
s, r = call("GET", "/attendance/board?date=" + dstr(), token=A, now=at(18))
check("board shows automatic statuses", s == 200 and r["counts"]["half_day"] >= 1 and r["counts"]["late"] == 1, (s, r.get("counts") if isinstance(r, dict) else r))
check("nobody checked in counts as absent after the shift", r["counts"]["absent"] == 1, r["counts"])
s, r = call("GET", "/attendance/board?date=" + dstr(), token=A, now=at(10))
check("before shift end -> not_in, not absent", r["counts"]["not_in"] >= 1, r["counts"])

# ---------------------------------------------------------------- locked profile + change requests
section("Employees cannot edit HR-entered data")
s, r = call("PUT", "/profile", {"phone": "0100"}, T1)
check("PUT /profile phone refused", s == 403, (s, r))
s, r = call("PUT", "/auth/profile", {"name": "Hacker"}, T1)
check("PUT /auth/profile name refused", s == 403, (s, r))
s, r = call("PUT", f"/employees/{E1}", {"salary": 99999}, T1)
check("employee cannot raise own salary", s == 403, (s, r))
s, r = call("PUT", "/profile", {"avatar": "/uploads/avatars/x.png"}, T1)
check("employee may set own photo", s == 200, (s, r))
s, r = call("POST", "/requests", {"type": "profile_change", "payload": {"changes": {"phone": "01001234567", "address": "Cairo"}}}, T1)
check("profile change request filed", s == 201 and r["payload"]["changes"]["phone"]["to"] == "01001234567", (s, r))
RQ = r["id"]
s, r = call("PUT", f"/requests/{RQ}", {"status": "approved"}, T1)
check("employee cannot approve own request", s == 403, (s, r))
s, r = call("PUT", f"/requests/{RQ}", {"status": "approved"}, A)
check("HR approves profile change", s == 200 and r["status"] == "approved", (s, r))
s, r = call("GET", f"/employees/{E1}", token=A)
check("approved change applied to the employee", r["phone"] == "01001234567" and r["address"] == "Cairo", r)
s, r = call("POST", "/requests", {"type": "profile_change", "payload": {"changes": {"phone": "01001234567"}}}, T1)
check("no-op change refused", s == 422, (s, r))

section("Attendance correction request")
s, r = call("POST", "/requests", {"type": "attendance_correction", "payload": {"date": dstr(-1 + 0), "check_in": "09:00", "check_out": "17:00", "reason": "App was down"}}, T4, now=at(12))
check("correction for a future day refused or allowed only for past", s in (201, 422), (s, r))
s, r = call("POST", "/requests", {"type": "attendance_correction", "payload": {"date": dstr(0), "check_in": "09:00", "check_out": "17:00", "reason": "Phone died, I arrived on time"}}, T4, now=at(18))
check("correction request filed", s == 201, (s, r))
RC = r["id"]
s, r2 = call("POST", "/requests", {"type": "attendance_correction", "payload": {"date": dstr(0), "check_in": "09:00", "check_out": "17:00"}}, T4, now=at(18))
check("duplicate pending correction refused", s == 409, (s, r2))
s, r = call("PUT", f"/requests/{RC}", {"status": "approved", "reviewNote": "ok"}, A, now=at(18, 5))
check("HR approves correction", s == 200, (s, r))
s, r = call("GET", f"/attendance?employee_id={E4}&date={dstr()}", token=A, now=at(18, 10))
check("correction rewrote the day -> present", s == 200 and len(r) == 1 and r[0]["status"] == "present" and r[0]["source"] == "correction", (s, r))

# ---------------------------------------------------------------- zones: location + Wi-Fi
section("Location and Wi-Fi rules")
s, r = call("POST", "/attendance-rules", {"name": "HQ", "isActive": True, "locationEnabled": True, "locationLat": 30.0444, "locationLng": 31.2357, "locationRadiusKm": 0.2}, A)
check("location rule", s == 200, (s, r))
RULE1 = r["id"]
s, r = call("POST", "/attendance-rules", {"name": "Branch", "isActive": True, "locationEnabled": True, "locationLat": 31.2001, "locationLng": 29.9187, "locationRadiusKm": 0.3}, A)
check("second active rule allowed (several branches)", s == 200 and r["isActive"], (s, r))
s, r = call("POST", "/attendance-rules", {"name": "Bad", "locationEnabled": True, "locationLat": 999, "locationLng": 0}, A)
check("impossible coordinates rejected", s == 422, (s, r))
d1 = 1
s, r = call("POST", "/attendance/check-in", {"lat": 31.2003, "lng": 29.9189}, T1, now=at(9, 0, d1))
check("check-in at the second branch works", s == 201 and r["status"] == "present", (s, r))
s, r = call("POST", "/attendance/ping", {"lat": 30.0445, "lng": 31.2358}, T1, now=at(9, 30, d1))
check("ping inside (other branch) keeps inside", s == 200 and r["inside"] is True, (s, r))
s, r = call("POST", "/attendance/ping", {"lat": 29.0, "lng": 30.0}, T1, now=at(10, 0, d1))
check("ping outside -> minutes counted", s == 200 and r["inside"] is False and r["outZoneMinutes"] == 30, (s, r))
s, r = call("POST", "/attendance/ping", {"lat": 29.0, "lng": 30.0}, T1, now=at(10, 30, d1))
check("still outside -> accumulates", r["outZoneMinutes"] == 60, r)
s, r = call("POST", "/attendance/ping", {"lat": 29.0, "lng": 30.0}, T1, now=at(11, 0, d1))
check("120 outside minutes -> half day automatically", r["outZoneMinutes"] == 90, r)
s, r = call("POST", "/attendance/ping", {"lat": 29.0, "lng": 30.0}, T1, now=at(11, 30, d1))
check("reaching the policy limit makes today a half day", r["outZoneMinutes"] == 120 and r["status"] == "half_day", r)
s, r = call("POST", "/attendance/check-out", {"lat": 30.0445, "lng": 31.2358}, T1, now=at(17, 0, d1))
check("check-out keeps the automatic half day", s == 200 and r["status"] == "half_day" and r["outZoneMinutes"] == 120, (s, r))
s, r = call("GET", "/notifications", token=A)
check("HR was told about the employee leaving the zone", any(n["type"] == "left_zone" for n in r["items"]), r)

s, r = call("PUT", f"/attendance-rules/{RULE1}", {"isActive": False}, A)
s, rr = call("GET", "/attendance-rules", token=A)
for x in rr:
    if x["name"] == "Branch":
        call("DELETE", f"/attendance-rules/{x['id']}", token=A)
s, r = call("POST", "/attendance-rules", {"name": "Wifi", "isActive": True, "wifiEnabled": True, "wifiSsid": "Office-WiFi"}, A)
WIFI = r["id"]
d2 = 2
s, r = call("POST", "/attendance/check-in", {}, T2, now=at(9, 0, d2))
check("Wi-Fi rule: no SSID -> refused with explanation", s == 422 and "Wi-Fi" in json.dumps(r), (s, r))
s, r = call("POST", "/attendance/check-in", {"ssid": "<unknown ssid>"}, T2, now=at(9, 0, d2))
check("Wi-Fi rule: unreadable SSID -> clear hint", s == 422 and "location services" in json.dumps(r), (s, r))
s, r = call("POST", "/attendance/check-in", {"ssid": "Other-Net"}, T2, now=at(9, 0, d2))
check("Wi-Fi rule: wrong network refused", s == 422, (s, r))
s, r = call("POST", "/attendance/check-in", {"ssid": "\"office-wifi\""}, T2, now=at(9, 0, d2))
check("Wi-Fi rule: right network (quotes/case ignored)", s == 201, (s, r))
call("PUT", f"/attendance-rules/{WIFI}", {"locationEnabled": True, "locationLat": 30.0444, "locationLng": 31.2357, "locationRadiusKm": 0.2, "matchMode": "all"}, A)
s, r = call("POST", "/attendance/check-in", {"ssid": "Office-WiFi"}, T3, now=at(9, 0, d2))
check("mode=all: Wi-Fi alone is not enough", s == 422, (s, r))
call("PUT", f"/attendance-rules/{WIFI}", {"matchMode": "any"}, A)
s, r = call("POST", "/attendance/check-in", {"lat": 30.0445, "lng": 31.2358}, T3, now=at(9, 0, d2))
check("mode=any: location alone is enough", s == 201, (s, r))
call("DELETE", f"/attendance-rules/{WIFI}", token=A)

# ---------------------------------------------------------------- missed check-out, absence
section("Missed check-out closes the day")
# T2 checked in on d2 and never left; next morning the day is closed and flagged
s, r = call("GET", "/attendance/today", token=T2, now=at(8, 0, 3))
check("new day: previous open day no longer blocks", s == 200 and r["state"] == "ready", (s, r))
s, r = call("GET", f"/attendance?employee_id={E2}&date={dstr(d2)}", token=A, now=at(8, 0, 3))
check("unclosed day flagged missed_checkout", r and "missed_checkout" in (r[0]["flags"] or ""), r)

# ---------------------------------------------------------------- reward points
section("Reward points")
s, r = call("PUT", "/points/config", {"streakDays": 3}, T1)
check("employee cannot change the rules", s == 403, (s, r))
s, r = call("PUT", "/points/config", {"streakDays": 3, "redCost": 2, "blackCost": 5}, A)
check("admin sets 3-day streak", s == 200 and r["streakDays"] == 3, (s, r))

# Eve: a fresh employee whose points start counting on the day before the schedule below
E5, T5 = new_employee("Eve")
base = 10          # days after MONDAY; day 10 is a Thursday
call("GET", "/points/me", token=T5, now=at(8, 0, base - 1))   # starts counting from here
seq = [  # (day offset, in, out)
    (base + 0, (9, 0), (17, 0)),     # Thu   green
    (base + 1, (9, 5), (17, 0)),     # Fri   weekend -> skipped
    (base + 3, (9, 0), (17, 0)),     # Sun   green
    (base + 4, (11, 30), (17, 0)),   # Mon   half day -> red
    # Tue base+5 : no attendance -> absent -> black
    (base + 6, (9, 0), (17, 0)),     # Wed   green
    (base + 7, (9, 0), (17, 0)),     # Thu   green
    (base + 10, (9, 0), (17, 0)),    # Sun   green   -> 3 greens in a row = level up
]
for day, i, o in seq:
    s, r = call("POST", "/attendance/check-in", {}, T5, now=at(i[0], i[1], day))
    assert s == 201, (day, s, r)
    s, r = call("POST", "/attendance/check-out", {}, T5, now=at(o[0], o[1], day))
    assert s == 200, (day, s, r)
    if day == base + 0:
        check("on-time day gives a green point", r.get("reward") and r["reward"]["color"] == "green", r)
s, r = call("GET", "/points/me", token=T5, now=at(8, 0, base + 11))
check("points summary works", s == 200, (s, r))
raw = r["raw"]
check("raw colours: 5 green, 1 red, 1 black", raw == {"green": 5, "red": 1, "black": 1}, raw)
check("5 greens cancel the black (black first), red stays", r["net"] == {"green": 0, "red": 1, "black": 0} and r["cancelled"]["black"] == 1, r)
check("3 green days in a row = level 1", r["level"] == 1 and r["levelName"] == "Bronze", (r["level"], r["levelName"], r["streak"]))
s, n = call("GET", "/notifications", token=T5)
check("level-up notification sent", any(x["type"] == "level_up" for x in n["items"]), n)

s, r = call("POST", "/points/adjust", {"employeeId": E5, "color": "green", "note": "Great teamwork"}, A, now=at(9, 0, base + 11))
check("HR gives a manual green", s == 201 and r["raw"]["green"] == 6, (s, r))
s, r = call("POST", "/points/adjust", {"employeeId": E5, "color": "green"}, T5)
check("employee cannot give points", s == 403)
red_row = [h for h in r.get("history", [])] if isinstance(r, dict) else []
s, sm = call("GET", f"/points/employee/{E5}", token=A, now=at(9, 0, base + 11))
reds = [h for h in sm["history"] if h["color"] == "red"]
s, r = call("PUT", f"/points/{reds[0]['id']}", {"voided": True}, A)
check("HR excuses the red day", s == 200 and r["raw"]["red"] == 0, (s, r))
s, r = call("GET", "/points/leaderboard", token=T1, now=at(9, 0, base + 11))
check("leaderboard visible to employees", s == 200 and len(r["items"]) >= 1 and r["items"][0]["rank"] == 1, (s, r))
call("PUT", "/points/config", {"showLeaderboard": False}, A)
s, r = call("GET", "/points/leaderboard", token=T1, now=at(9, 0, base + 11))
check("admin can hide the leaderboard from employees", s == 403, (s, r))
s, r = call("GET", "/points/leaderboard", token=A, now=at(9, 0, base + 11))
check("HR still sees it", s == 200, (s, r))
call("PUT", "/points/config", {"showLeaderboard": True, "lateColor": "red"}, A)
s, r = call("GET", "/points/config", token=T1)
check("employees can read the rules", s == 200 and r["lateColor"] == "red", (s, r))

# ---------------------------------------------------------------- promotions + departments
section("Promotions and department heads")
s, r = call("POST", f"/employees/{E1}/promote", {"type": "promotion", "position": "Senior Clerk", "salary": 4500, "note": "Great year"}, T1)
check("employee cannot promote", s == 403, (s, r))
s, r = call("POST", f"/employees/{E1}/promote", {"type": "promotion", "position": "Senior Clerk", "salary": 4500, "note": "Great year"}, A)
check("HR promotes: position + salary changed now", s == 201 and r["employee"]["position"] == "Senior Clerk" and float(r["employee"]["salary"]) == 4500, (s, r))
s, r = call("GET", f"/employees/{E1}/promotions", token=T1)
check("employee sees own career history", s == 200 and len(r) == 1 and r[0]["fromPosition"] == "Clerk" and r[0]["toPosition"] == "Senior Clerk", (s, r))
s, r = call("GET", f"/employees/{E2}/promotions", token=T1)
check("employee cannot see a colleague's history", s == 403, (s, r))
s, n = call("GET", "/notifications", token=T1)
check("employee was notified", any(x["type"] == "promotion" for x in n["items"]), n)
s, r = call("POST", f"/employees/{E2}/promote", {"type": "raise", "salary": 3600, "effectiveDate": dstr(400)}, A)
check("future-dated raise is scheduled, not applied", s == 201 and float(r["employee"]["salary"]) == 3000, (s, r))
s, r = call("POST", f"/employees/{E2}/promote", {"type": "raise"}, A)
check("promotion needs a change", s == 422)

s, r = call("PUT", f"/departments/{DEP}", {"headId": E3}, A)
check("employee can be made department head", s == 200 and r["headEmployeeId"] == E3 and r["headName"].startswith("Cid"), (s, r))
s, e = call("GET", f"/employees/{E2}", token=A)
check("members without a manager now report to the head", e["managerId"] == E3, e)
s, d2r = call("POST", "/departments", {"name": "Sales"}, A)
SAL = d2r["id"]
s, r = call("POST", f"/departments/{SAL}/members", {"employeeIds": [E1, E2]}, A)
check("add employees to a department", s == 200 and len(r["members"]) == 2, (s, r))
s, r = call("PUT", f"/departments/{SAL}", {"headId": E1}, A)
s, r = call("DELETE", f"/departments/{SAL}/members/{E1}", token=A)
check("removing the head from the department clears the head", s == 200 and not r.get("headEmployeeId") and len(r["members"]) == 1, (s, r))
s, r = call("GET", "/org", token=T1)
check("org chart available to employees", s == 200 and any(d["name"] == "Ops" and d["head"] for d in r["departments"]), (s, r))

# ---------------------------------------------------------------- payroll from attendance
section("Payroll built from attendance")
s, r = call("GET", f"/payroll/preview?employeeId={E4}&month={dstr(base)[:7]}", token=A, now=at(23, 0, base + 40))
check("payroll preview works", s == 200 and "breakdown" in r, (s, r))
s, r = call("GET", "/payroll/preview?employeeId=%d&month=%s" % (E4, dstr(base)[:7]), token=T4)
check("employees cannot preview payroll", s == 403)
s, r = call("POST", "/payroll/generate", {"month": dstr(base)[:7]}, A, now=at(23, 0, base + 40))
check("generate payslips", s == 200 and r["created"] >= 1, (s, r))
s, r = call("GET", f"/payroll?employeeId={E4}&month={dstr(base)[:7]}", token=A)
check("absence/half-day reduced the salary", s == 200 and len(r) == 1 and float(r[0]["deductions"]) > 0 and r[0]["breakdown"], (s, r))
s, r2 = call("GET", f"/payroll/{r[0]['id']}", token=T4)
check("employee reads own payslip with breakdown", s == 200 and r2["breakdown"]["lines"], (s, r2))

# ---------------------------------------------------------------- reports, audit, exit
section("Reports, audit log, offboarding")
s, r = call("GET", f"/reports/attendance?month={dstr(base)[:7]}", token=A, now=at(23, 0, base + 40))
check("attendance report", s == 200 and r["rows"] and "absent" in r["columns"], (s, r))
s, txt = call("GET", f"/reports/attendance?month={dstr(base)[:7]}&format=csv", token=A, raw=True, now=at(23, 0, base + 40))
check("CSV export (Excel-ready)", s == 200 and txt.startswith("﻿") and "Employee" in txt, txt[:100] if isinstance(txt, str) else txt)
s, r = call("GET", "/reports/employees", token=T1)
check("employees cannot open reports", s == 403)
s, r = call("GET", "/audit", token=A)
check("audit log lists actions", s == 200 and len(r) > 5 and any(x["entity"] == "employee" for x in r), (s, r))
s, r = call("GET", "/audit", token=T1)
check("employees cannot read the audit log", s == 403)
s, r = call("POST", f"/employees/{E3}/terminate", {"reason": "Resigned"}, A)
check("terminate employee", s == 200 and r["status"] == "inactive" and r["terminationReason"] == "Resigned", (s, r))
s, dd = call("GET", f"/departments/{DEP}", token=A)
check("leaver is no longer department head", not dd.get("headEmployeeId"), dd)
s, r = call("GET", "/attendance/today", token=T3)
check("terminated employee is signed out", s == 401, (s, r))
s, r = call("POST", f"/employees/{E3}/reinstate", token=A)
check("reinstate", s == 200 and r["status"] == "active", (s, r))

print(f"\n{passed} passed, {failed} failed")
if failures:
    print("FAILED:")
    for f in failures:
        print("  -", f)
sys.exit(1 if failed else 0)
