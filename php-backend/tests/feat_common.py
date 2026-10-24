"""Shared helpers for the premium-feature tests (api_test16..21).
Usage:  python api_test16_local_laws.py http://127.0.0.1:8098 [mysql.exe] [port] [database]
"""
import json, subprocess, sys, urllib.request, urllib.error, uuid

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8098") + "/api"
MYSQL = sys.argv[2] if len(sys.argv) > 2 else r"C:\laragon\bin\mysql\mysql-8.4.3-winx64\bin\mysql.exe"
PORT = sys.argv[3] if len(sys.argv) > 3 else "3399"
DB = sys.argv[4] if len(sys.argv) > 4 else "grouptest"
RUN = uuid.uuid4().hex[:6]
PW = "Pass12345!"
state = {"ok": 0, "fail": 0}


def call(method, path, body=None, token=None, raw=False):
    req = urllib.request.Request(BASE + path, method=method, data=json.dumps(body).encode() if body is not None else None)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        r = urllib.request.urlopen(req)
        data = r.read()
        return r.status, (data if raw else json.loads(data or b"{}"))
    except urllib.error.HTTPError as e:
        data = e.read()
        if raw:
            return e.code, data
        try:
            return e.code, json.loads(data or b"{}")
        except Exception:
            return e.code, {}


def check(name, cond, extra=""):
    if cond:
        state["ok"] += 1; print("  ok  ", name)
    else:
        state["fail"] += 1; print("  FAIL", name, extra)


def sql(q):
    subprocess.run([MYSQL, "-h127.0.0.1", f"-P{PORT}", "-uroot", DB, "-e", q], check=True, capture_output=True)


def sql_out(q):
    r = subprocess.run([MYSQL, "-h127.0.0.1", f"-P{PORT}", "-uroot", "-N", DB, "-e", q], check=True, capture_output=True)
    return r.stdout.decode().strip()


def company(tag):
    """(token, user_id, company_id) of a fresh company admin."""
    sql("DELETE FROM throttle")          # the sign-up limiter would stop a test run (test rig only)
    s, r = call("POST", "/companies/register", {"companyName": f"F{tag} {RUN}", "name": f"Admin {tag}", "email": f"admin{tag}{RUN}@feat.test", "password": PW})
    assert s == 201, (s, r)
    return r["token"], r["user"]["id"], r["company"]["id"]


def employee(hr, tag, **extra):
    """(token, employee_id, user_id) of a new activated employee."""
    em = f"{tag}{RUN}@feat.test"
    body = {"first_name": tag, "last_name": "Emp", "email": em}
    body.update(extra)
    s, e = call("POST", "/employees", body, hr)
    assert s == 201, (s, e)
    s, r = call("POST", "/auth/employee/activate", {"email": em, "code": e.get("inviteCode"), "password": PW})
    assert r.get("token"), (s, r)
    return r["token"], e["id"], r["user"]["id"]


_owner = {}


def owner_token():
    """A platform owner (created once per run, server-side) that can switch features."""
    if not _owner:
        tok, uid, cid_ = company("owner")
        sql(f"INSERT INTO platform_owners (user_id) VALUES ({uid})")
        _owner["tok"] = tok
        _owner["cid"] = cid_
    return _owner["tok"]


def owner_company():
    owner_token()
    return _owner["cid"]


def switch(company_id, **flags):
    """Owner switches features (snake or camel keys) for a company."""
    s, r = call("PUT", f"/owner/companies/{company_id}/features", {"flags": flags}, owner_token())
    assert s == 200, (s, r)
    return r


def finish():
    print(f"\n{state['ok']} passed, {state['fail']} failed")
    sys.exit(1 if state["fail"] else 0)
