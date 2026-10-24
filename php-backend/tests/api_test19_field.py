"""Feature field_proof: visits with GPS, photo, route and signature; who may see them; files are protected.
Run:  python api_test19_field.py http://127.0.0.1:8098
"""
import base64, struct, time, urllib.request, urllib.error, zlib
from feat_common import *


def png(w=8, h=8, color=(200, 30, 30)):
    raw = b"".join(b"\x00" + bytes(color) * w for _ in range(h))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")


PHOTO = base64.b64encode(png(color=(10, 120, 200))).decode()
SIG = base64.b64encode(png(color=(0, 0, 0))).decode()

print("== setup")
hr, hr_uid, C = company("field")
boss_tok, BOSS, _ = employee(hr, "boss", salary=15000)
rep_tok, REP, _ = employee(hr, "rep", salary=7000, manager_id=BOSS)
rep2_tok, REP2, _ = employee(hr, "rep2", salary=7000)
other_tok, OTH, _ = employee(hr, "other", salary=7000)
LAT, LNG = 30.0444, 31.2357            # Cairo

print("== closed until switched on")
s, r = call("GET", "/field/visits", None, rep_tok)
check("closed while off", s == 403 and r.get("code") == "feature_disabled", f"{s} {r}")
switch(C, field_proof=True)

print("== start a visit")
s, r = call("POST", "/field/visits", {"customer_name": "", "lat": LAT, "lng": LNG}, rep_tok)
check("customer name required", s == 422, f"{s}")
s, r = call("POST", "/field/visits", {"customer_name": "Mahmoud Store", "lat": None, "lng": None}, rep_tok)
check("location required", s == 422, f"{s}")
s, r = call("POST", "/field/visits", {"customer_name": "Mahmoud Store", "lat": 200, "lng": LNG}, rep_tok)
check("impossible latitude refused", s == 422, f"{s}")
s, r = call("POST", "/field/visits", {"customer_name": "Mahmoud Store", "lat": LAT, "lng": LNG, "photo_base64": base64.b64encode(b"not an image at all").decode()}, rep_tok)
check("a non-image 'photo' is refused", s == 422, f"{s} {r}")
s, r = call("POST", "/field/visits", {"customer_name": "Mahmoud Store", "customer_phone": "0100", "address": "12 Tahrir St", "purpose": "Collect cheque", "lat": LAT, "lng": LNG, "photo_base64": PHOTO}, rep_tok)
check("visit started with a photo", s == 201 and r["status"] == "active" and r["hasPhoto"] is True, f"{s} {r}")
V = r["id"]
s, r = call("POST", "/field/visits", {"customer_name": "Second", "lat": LAT, "lng": LNG}, rep_tok)
check("only one visit in progress at a time", s == 409 and r.get("activeVisitId") == V, f"{s} {r}")
s, r = call("POST", "/field/visits", {"customer_name": "HR cannot", "lat": LAT, "lng": LNG}, hr)
check("an account without an employee record cannot start one", s == 403, f"{s}")

print("== route points")
now = int(time.time())
pts = [{"lat": LAT + 0.001 * i, "lng": LNG, "t": now - 30 + i * 5} for i in range(1, 6)]   # ~111 m apart each
s, r = call("POST", f"/field/visits/{V}/points", {"points": pts}, rep_tok)
check("points stored and distance counted (~555 m)", s == 200 and r["added"] == 5 and 500 <= r["distanceM"] <= 600, f"{s} {r}")
s, r = call("POST", f"/field/visits/{V}/points", {"points": [{"lat": 91, "lng": 0}, {"lat": "x", "lng": 1}]}, rep_tok)
check("garbage points are skipped, not stored", s == 200 and r["added"] == 0, f"{s} {r}")
s, r = call("POST", f"/field/visits/{V}/points", {"points": [{"lat": LAT + 20, "lng": LNG}]}, rep_tok)
check("a 2000 km GPS jump does not add distance", s == 200 and r["distanceM"] < 700, f"{r}")
s, r = call("POST", f"/field/visits/{V}/points", {"points": pts}, rep2_tok)
check("somebody else cannot add points", s in (403, 404), f"{s}")
s, r = call("POST", f"/field/visits/{V}/points", {"points": []}, rep_tok)
check("empty batch refused", s == 422, f"{s}")

print("== finish with the customer's signature")
s, r = call("POST", f"/field/visits/{V}/finish", {"lat": LAT + 0.006, "lng": LNG, "signature_base64": base64.b64encode(b"junk").decode()}, rep_tok)
check("junk signature refused", s == 422, f"{s}")
s, r = call("POST", f"/field/visits/{V}/finish", {"lat": LAT + 0.006, "lng": LNG, "signature_base64": SIG, "signed_name": "Mahmoud", "notes": "Cheque collected"}, rep_tok)
check("visit finished (photo + signature + long enough: only 'very_short' may show in a fast test)", s == 200 and r["status"] == "done" and r["hasSignature"] and r["hasPhoto"] and r["signedName"] == "Mahmoud" and not {"no_photo", "no_signature"} & set(r["flags"]), f"{s} {r}")
s, r = call("POST", f"/field/visits/{V}/finish", {"lat": LAT, "lng": LNG}, rep_tok)
check("a closed visit cannot be finished again", s == 409, f"{s}")
s, r = call("POST", f"/field/visits/{V}/points", {"points": pts}, rep_tok)
check("nor receive more points", s == 409, f"{s}")

print("== a sloppy visit is flagged")
s, r = call("POST", "/field/visits", {"customer_name": "Quick", "lat": LAT, "lng": LNG}, rep_tok)
V2 = r["id"]
s, r = call("POST", f"/field/visits/{V2}/finish", {"lat": LAT, "lng": LNG}, rep_tok)
check("no photo, no signature, very short are all flagged", set(r["flags"]) >= {"no_photo", "no_signature", "very_short"}, f"{r}")
s, r = call("GET", "/notifications", None, boss_tok)
check("the manager is told about the gap", any(n.get("type") == "field" for n in r.get("items", [])), f"{r}")
s, r = call("POST", "/field/visits", {"customer_name": "Cancelled one", "lat": LAT, "lng": LNG}, rep_tok)
V3 = r["id"]
s, r = call("POST", f"/field/visits/{V3}/cancel", None, rep_tok)
check("a visit can be cancelled", s == 200 and r["status"] == "cancelled", f"{s} {r}")

print("== who sees what")
s, r = call("GET", "/field/visits", None, rep_tok)
check("the rep sees their own visits", s == 200 and len(r) == 3, f"{len(r)}")
s, r = call("GET", "/field/visits", None, boss_tok)
check("the manager sees their team's", s == 200 and len(r) == 3 and all(v["employeeId"] == REP for v in r), f"{len(r)}")
s, r = call("GET", "/field/visits", None, other_tok)
check("a colleague sees nothing", s == 200 and r == [], f"{r}")
s, r = call("GET", "/field/visits?status=done", None, hr)
check("HR sees all, can filter", s == 200 and len(r) == 2 and all(v["status"] == "done" for v in r), f"{len(r)}")
s, r = call("GET", f"/field/visits/{V}", None, other_tok)
check("a colleague cannot open a visit", s == 404, f"{s}")
s, r = call("GET", f"/field/visits/{V}", None, boss_tok)
check("the manager opens it with the route", s == 200 and len(r["route"]) >= 7 and any(abs(p["lat"] - LAT) < 1e-6 for p in r["route"]), f"{s} {len(r.get('route', []))}")


def get_file(path, tok):
    req = urllib.request.Request(BASE + path, headers={"Authorization": "Bearer " + tok} if tok else {})
    try:
        r = urllib.request.urlopen(req)
        return r.status, r.headers.get("Content-Type"), r.read()
    except urllib.error.HTTPError as e:
        return e.code, None, b""


print("== files are streamed only after an access check")
s, ct, data = get_file(f"/field/file/{V}/photo", boss_tok)
check("the manager can fetch the photo (a real PNG)", s == 200 and ct == "image/png" and data[:4] == b"\x89PNG", f"{s} {ct}")
s, ct, data = get_file(f"/field/file/{V}/signature", hr)
check("HR can fetch the signature", s == 200 and data[:4] == b"\x89PNG", f"{s}")
s, ct, data = get_file(f"/field/file/{V}/photo", other_tok)
check("a colleague cannot", s == 404, f"{s}")
s, ct, data = get_file(f"/field/file/{V}/photo", None)
check("nobody without a token can", s == 401, f"{s}")
s, ct, data = get_file(f"/field/file/{V2}/signature", hr)
check("no signature = 404", s == 404, f"{s}")

print("== summary")
s, r = call("GET", "/field/summary", None, boss_tok)
rep_row = [p for p in r["people"] if p["employeeId"] == REP][0]
check("manager summary: visits, km, signed", s == 200 and rep_row["visits"] == 2 and rep_row["signed"] == 1 and rep_row["km"] >= 0.5, f"{rep_row}")
s, r = call("GET", "/field/summary", None, rep_tok)
check("a normal employee has no summary", s == 403, f"{s}")

print("== off closes it, data stays")
switch(C, field_proof=False)
s, r = call("POST", "/field/visits", {"customer_name": "x", "lat": LAT, "lng": LNG}, rep_tok)
check("cannot start while off", s == 403 and r.get("code") == "feature_disabled", f"{s}")
s, ct, data = get_file(f"/field/file/{V}/photo", boss_tok)
check("photos are closed too", s == 403, f"{s}")
switch(C, field_proof=True)
s, r = call("GET", "/field/visits", None, rep_tok)
check("back on: history intact", s == 200 and len(r) == 3, f"{len(r)}")

finish()
