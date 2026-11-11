"""API smoke test: every endpoint, signed out and signed in, against a throwaway database.
Run: uv run python tests/smoke_api.py   (needs Docker; starts no boxes)"""
import base64
import json
import os
import sys
import tempfile
from pathlib import Path

os.environ["SADDB_DB"] = str(Path(tempfile.mkdtemp()) / "smoke.sqlite")
os.environ.setdefault("SADDB_SECRET_KEY", "smoke-test-key")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from fastapi.testclient import TestClient  # noqa: E402
from itsdangerous import TimestampSigner  # noqa: E402

from app import config, store  # noqa: E402
from app.main import app  # noqa: E402

fails = 0


def check(client, path, method="GET", want=200):
    global fails
    r = client.request(method, path)
    ok = r.status_code == want
    fails += not ok
    print(f"{'ok ' if ok else 'BAD'} {method} {path} -> {r.status_code}" + ("" if ok else f" (want {want}): {r.text[:200]}"))
    return r


with TestClient(app) as c:      # runs startup: DB init, reaper
    for p in ["/", "/api/me", "/api/tracks", "/api/scenarios/pg-wont-start", "/api/leaderboard",
              "/api/leaderboard?engine=redis&period=30d", "/api/scoring", "/t/postgres", "/s/pg-wont-start"]:
        check(c, p)
    check(c, "/api/me/history", want=401)
    check(c, "/api/scenarios/pg-wont-start/hint", "POST", want=401)

    uid = store.upsert_google_user("smoke-sub", "smoke@test.local", "Smoke", "")
    c.cookies.set("saddb_session", TimestampSigner(config.SECRET_KEY).sign(base64.b64encode(json.dumps({"uid": uid}).encode())).decode())
    me = check(c, "/api/me").json()
    if not me.get("user") or me["user"]["id"] != uid or "points" not in me:
        fails += 1
        print("BAD /api/me signed in:", me)
    for p in ["/api/tracks", "/api/me/history", "/api/scenarios/redis-oom", "/api/leaderboard"]:
        check(c, p)
    check(c, "/api/scenarios/redis-oom/hint", "POST")
    check(c, "/api/sessions/doesnotexist", want=404)

print("PASS" if not fails else f"FAIL ({fails})")
sys.exit(1 if fails else 0)
