"""Attendance access: company rules for everybody, per-person exceptions (another place / no place check), HR blocks, attempts are logged.
Run:  python api_test27_attendance_access.py http://127.0.0.1:8098 [mysql.exe] [port] [database]
"""
from feat_common import *

print("== setup")
hr, hr_uid, CO = company("aa")
A = (24.7136, 46.6753)      # the company workplace
B = (21.5433, 39.1728)      # another place
FAR = (30.0444, 31.2357)

s, ra = call("POST", "/attendance-rules", {"name": "Head office", "is_active": 1, "location_enabled": 1, "location_lat": A[0], "location_lng": A[1], "location_radius_km": 0.2}, hr)
check("company rule created", s in (200, 201), ra)
RA = ra["id"]
s, rb = call("POST", "/attendance-rules", {"name": "Branch", "is_active": 0, "location_enabled": 1, "location_lat": B[0], "location_lng": B[1], "location_radius_km": 0.2}, hr)
RB = rb["id"]

t1, e1, _ = employee(hr, "aa1")
t2, e2, _ = employee(hr, "aa2")
t3, e3, _ = employee(hr, "aa3")
t4, e4, _ = employee(hr, "aa4")


def cin(tok, p):
    return call("POST", "/attendance/check-in", {"lat": p[0], "lng": p[1]}, tok)


print("== everybody follows the company rule")
s, r = cin(t1, FAR)
check("away from the workplace is refused", s == 422, f"{s} {r}")
s, r = call("GET", f"/employees/{e1}/attendance-attempts", None, hr)
check("the attempt is kept for HR", s == 200 and len(r) == 1 and r[0]["action"] == "check_in", f"{s} {r}")
s, r = call("GET", "/notifications", None, hr)
check("HR is told", s == 200 and "away from the workplace" in str(r), str(r)[:300])
s, r = cin(t1, A)
check("at the workplace works", s == 201, f"{s} {r}")

print("== exception: another place for one person")
s, r = call("PUT", f"/employees/{e2}/attendance-access", {"attendance_mode": "rule", "attendance_rule_id": RB}, hr)
check("HR assigns the branch rule", s == 200 and r["attendanceMode"] == "rule" and r["attendanceRuleId"] == RB, f"{s} {r}")
s, r = cin(t2, A)
check("the company place no longer works for this person", s == 422, f"{s} {r}")
s, r = cin(t2, B)
check("the branch works", s == 201, f"{s} {r}")

print("== exception: no place check")
s, r = call("PUT", f"/employees/{e3}/attendance-access", {"attendance_mode": "free"}, hr)
check("HR frees one person", s == 200 and r["attendanceMode"] == "free", f"{s} {r}")
s, r = cin(t3, FAR)
check("works from anywhere", s == 201, f"{s} {r}")

print("== HR blocks one person")
s, r = call("PUT", f"/employees/{e4}/attendance-access", {"attendance_block": 1, "attendance_blocked": True, "attendance_block_reason": "Outside the workplace"}, hr)
check("blocked", s == 200 and r["attendanceBlocked"] in (1, True), f"{s} {r}")
s, r = cin(t4, A)
check("a blocked person cannot check in (403, with the reason)", s == 403 and "blocked" in r.get("error", "") and "Outside the workplace" in r.get("error", ""), f"{s} {r}")
s, r = call("PUT", f"/employees/{e4}/attendance-access", {"attendance_blocked": False}, hr)
check("unblocked", s == 200 and r["attendanceBlocked"] in (0, False), f"{s} {r}")
s, r = cin(t4, A)
check("works again", s == 201, f"{s} {r}")

print("== guards")
s, r = call("PUT", f"/employees/{e1}/attendance-access", {"attendance_mode": "weird"}, hr)
check("unknown mode refused", s == 422, f"{s} {r}")
s, r = call("PUT", f"/employees/{e1}/attendance-access", {"attendance_mode": "rule", "attendance_rule_id": 999999}, hr)
check("a rule of another company refused", s == 422, f"{s} {r}")
s, r = call("PUT", f"/employees/{e1}/attendance-access", {"attendance_mode": "free"}, t1)
check("an employee cannot change it", s == 403, f"{s} {r}")
s, r = call("GET", f"/employees/{e1}/attendance-attempts", None, t1)
check("an employee cannot read the attempts", s == 403, f"{s} {r}")
finish()
