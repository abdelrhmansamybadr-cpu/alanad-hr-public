"""Attendance is counted only from the day the employee created the account (first sign-in).
Run:  python api_test28_tracking_start.py http://127.0.0.1:8098 [mysql.exe] [port] [database]
"""
from feat_common import *

hr, hr_uid, CO = company("tr")
s, e = call("POST", "/employees", {"firstName": "Not", "lastName": "Yet", "phone": "05" + str(int(RUN, 16) % 90000000 + 10000000)}, hr)
EID = e["id"]
check("a new employee has no first sign-in yet", s == 201 and not e.get("firstSigninAt"), e)

s, b = call("GET", "/attendance/board", None, hr)
row = [x for x in b["employees"] if x["employeeId"] == EID]
check("the board does not count him as absent / not in", s == 200 and row and row[0]["boardStatus"] == "not_started" and b["counts"]["not_started"] >= 1, str(row)[:300])

s, r = call("GET", f"/attendance/summary?employeeId={EID}&month=1&year=2026", None, hr)
check("no absent days are counted for a month before sign-in", s == 200 and r["absentDays"] == 0, r)

t, eid2, _ = employee(hr, "trk")
s, e2 = call("GET", f"/employees/{eid2}", None, hr)
check("after the account is created the first sign-in is shown", s == 200 and e2.get("firstSigninAt"), e2)
s, b = call("GET", "/attendance/board", None, hr)
row = [x for x in b["employees"] if x["employeeId"] == eid2]
check("from then on he is tracked", row and row[0]["boardStatus"] != "not_started" and row[0]["trackingFrom"], str(row)[:300])
s, lst = call("GET", "/employees", None, hr)
check("the list shows who never signed in", [x for x in lst if x["id"] == EID][0].get("firstSigninAt") in (None, ""), "")
finish()
