"""sadDatabase: each play session is a disposable, network-less container with a broken database."""
import asyncio
import secrets
import threading
import time
from contextlib import asynccontextmanager
from pathlib import Path

import docker
from docker.errors import APIError, ImageNotFound, NotFound
from fastapi import Depends, FastAPI, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from starlette.middleware.sessions import SessionMiddleware

from . import config, scoring, store
from .catalog import ENGINES, load_scenarios, load_stories
from .auth import current_user, require_user, router as auth_router

STATIC = Path(__file__).resolve().parent / "static"
LABEL = "saddb.session"

SCENARIOS = load_scenarios()
STORIES = load_stories(SCENARIOS)   # also tags chapter scenarios with story + chapter

dk = docker.from_env()


def public(meta: dict, full: bool = False) -> dict:
    e = ENGINES[meta["engine"]]
    d = {k: meta.get(k) for k in ("slug", "engine", "title", "difficulty", "minutes", "tags", "summary", "order", "story", "chapter")}
    d["engine_name"] = f"{e['name']} {e['version']}"
    d["max_points"] = scoring.max_points(meta["difficulty"])
    if full:
        d["description"] = meta["description"]
        d["hints_total"] = len(meta.get("hints", []))
        d["narrative"] = meta.get("narrative")
        d["box_minutes"] = box_seconds(meta) // 60
        if meta.get("story"):           # story chapters: navigate in story order
            st = STORIES[meta["story"]]
            seq = [c for c in st["chapter_slugs"] if c in SCENARIOS]
            d["story_title"] = st["title"]
        else:                           # practice: navigate within the engine's track
            seq = [s["slug"] for s in SCENARIOS.values() if s["engine"] == meta["engine"] and not s.get("story")]
        i = seq.index(meta["slug"])
        d["next"] = seq[i + 1] if i + 1 < len(seq) else None
        d["prev"] = seq[i - 1] if i > 0 else None
        d["position"], d["track_size"] = i + 1, len(seq)
    return d


def box_seconds(meta: dict) -> int:
    """A box's initial lifetime: the scenario's box_minutes (long story chapters) or the default."""
    return int(meta["box_minutes"]) * 60 if meta.get("box_minutes") else config.BOX_SECONDS


def scorer_for(slug: str):
    m = SCENARIOS[slug]
    return lambda secs, hints, peeked, checks: scoring.compute(m["difficulty"], m.get("minutes", 15), secs, hints, peeked, checks)


def scenario(slug: str) -> dict:
    if slug not in SCENARIOS:
        raise HTTPException(404, "no such scenario")
    return SCENARIOS[slug]


_start_lock = threading.Lock()   # makes "one box per user" and the global cap atomic


def box_expiry(c) -> tuple[int, int]:
    """(expires_at, extensions) from the database; the container label is only a fallback."""
    t = store.box_times(c.labels[LABEL])
    if t and t["expires_at"]:
        return t["expires_at"], t["extensions"]
    return int(c.labels.get("saddb.expires", 0)), 0


def session_info(c) -> dict:
    exp, ext = box_expiry(c)
    return {"id": c.labels[LABEL], "slug": c.labels["saddb.slug"], "expires_at": exp, "status": c.status,
            "extensions_used": ext, "extensions_left": max(0, config.MAX_EXTENSIONS - ext),
            "extend_minutes": config.EXTEND_SECONDS // 60}


def user_boxes(uid: int):
    return dk.containers.list(filters={"label": [LABEL, f"saddb.owner={uid}"]})


def find(sid: str, user: dict):
    if not sid.isalnum():
        raise HTTPException(404, "no such session")
    cs = dk.containers.list(all=True, filters={"label": f"{LABEL}={sid}"})
    if not cs:
        raise HTTPException(404, "session expired or not found")
    if cs[0].labels.get("saddb.owner") != str(user["id"]):
        raise HTTPException(403, "not your session")
    return cs[0]


# ---------------------------------------------------------------- lifecycle

async def reaper():
    while True:
        try:
            now = time.time()
            boxes = dk.containers.list(all=True, filters={"label": LABEL})
            live = {c.labels[LABEL] for c in boxes}
            for sid in store.open_session_ids():       # boxes that vanished (host reboot, manual removal)
                if sid not in live:
                    store.end_attempt(sid, "lost")
            for c in boxes:
                if box_expiry(c)[0] < now or c.status == "exited":
                    store.end_attempt(c.labels[LABEL], "expired")
                    try:
                        c.remove(force=True, v=True)
                    except (NotFound, APIError):
                        pass
        except Exception as e:  # keep reaping whatever happens
            print("reaper:", e)
        await asyncio.sleep(30)


@asynccontextmanager
async def lifespan(_app):
    store.init()
    n = store.backfill_scores(SCENARIOS, scorer_for)
    if n:
        print(f"scored {n} earlier solves")
    task = asyncio.create_task(reaper())
    yield
    task.cancel()


app = FastAPI(title="sadDatabase", lifespan=lifespan)
app.add_middleware(SessionMiddleware, secret_key=config.SECRET_KEY, session_cookie="saddb_session",
                   max_age=30 * 86400, same_site="lax", https_only=config.SECURE_COOKIES)
app.include_router(auth_router)


# ---------------------------------------------------------------- catalogue

@app.get("/api/me")
def me(request: Request):
    u = current_user(request)
    if not u:
        return {"user": None, "google": bool(config.GOOGLE_CLIENT_ID), "dev_login": config.DEV_LOGIN}
    boxes = user_boxes(u["id"])
    board = store.leaderboard()
    rank = next((r["rank"] for r in board if r["id"] == u["id"]), None)
    return {"user": u, "active_session": session_info(boxes[0]) if boxes else None,
            "points": store.user_points(u["id"]), "rank": rank, "players": len(board)}


@app.get("/api/tracks")
def tracks(request: Request):
    u = current_user(request)
    prog = store.progress_for(u["id"]) if u else {}
    out = []
    for key, e in ENGINES.items():
        items = []
        for s in (s for s in SCENARIOS.values() if s["engine"] == key and not s.get("story")):
            p = prog.get(s["slug"], {})
            items.append(public(s) | {"solved": bool(p.get("first_solved_at")), "attempts": p.get("attempts", 0),
                                      "best_seconds": p.get("best_seconds"), "points": p.get("best_score")})
        out.append({"engine": key, **e, "scenarios": items, "solved": sum(i["solved"] for i in items),
                    "points": sum(i["points"] or 0 for i in items), "max_points": sum(i["max_points"] for i in items)})
    return out


def story_view(st: dict, prog: dict) -> dict:
    acts, n, done, pts, mx = [], 0, 0, 0, 0
    for act in st.get("acts", []):
        chapters = []
        for slug in act["chapters"]:
            n += 1
            if slug not in SCENARIOS:
                chapters.append({"slug": slug, "chapter": n, "coming_soon": True})
                continue
            p = prog.get(slug, {})
            c = public(SCENARIOS[slug]) | {"solved": bool(p.get("first_solved_at")), "attempts": p.get("attempts", 0),
                                          "best_seconds": p.get("best_seconds"), "points": p.get("best_score")}
            done += c["solved"]; pts += c["points"] or 0; mx += c["max_points"]
            chapters.append(c)
        acts.append({"title": act["title"], "intro": act.get("intro", ""), "chapters": chapters})
    nxt = next((c["slug"] for a in acts for c in a["chapters"] if not c.get("coming_soon") and not c["solved"]), None)
    e = ENGINES[st["engine"]]
    return {"id": st["id"], "title": st["title"], "subtitle": st.get("subtitle", ""), "engine": st["engine"],
            "engine_name": f"{e['name']} {e['version']}", "color": e["color"], "intro": st.get("intro", ""),
            "cast": st.get("cast", []), "acts": acts, "chapters": n, "solved": done, "points": pts, "max_points": mx,
            "next": nxt}


@app.get("/api/stories")
def stories(request: Request):
    u = current_user(request)
    prog = store.progress_for(u["id"]) if u else {}
    return [{k: v for k, v in story_view(st, prog).items() if k not in ("acts", "intro")} for st in STORIES.values()]


@app.get("/api/stories/{sid}")
def get_story(sid: str, request: Request):
    if sid not in STORIES:
        raise HTTPException(404, "no such story")
    u = current_user(request)
    return story_view(STORIES[sid], store.progress_for(u["id"]) if u else {})


@app.get("/api/scenarios/{slug}")
def get_scenario(slug: str, request: Request):
    s = scenario(slug)
    d = public(s, full=True)
    u = current_user(request)
    p = store.progress_for(u["id"]).get(slug, {}) if u else {}
    n = p.get("hints_revealed", 0)
    d["hints"] = s["hints"][:n]
    d["solution"] = s["solution"] if p.get("solution_viewed") else None
    d["solved"] = bool(p.get("first_solved_at"))
    d["best_seconds"] = p.get("best_seconds")
    d["points"] = p.get("best_score")
    base = scoring.BASE.get(s["difficulty"], 100)
    d["hint_cost"] = round(base * scoring.HINT_PENALTY)
    return d


@app.post("/api/scenarios/{slug}/hint")
def next_hint(slug: str, u: dict = Depends(require_user)):
    s = scenario(slug)
    r = store.reveal(u["id"], slug, len(s["hints"]))
    return {"hints": s["hints"][:r["hints_revealed"]]}


@app.post("/api/scenarios/{slug}/solution")
def show_solution(slug: str, u: dict = Depends(require_user)):
    s = scenario(slug)
    store.reveal(u["id"], slug, len(s["hints"]), solution=True)
    return {"solution": s["solution"]}


@app.get("/api/me/history")
def my_history(u: dict = Depends(require_user)):
    rows = store.history(u["id"])
    for r in rows:
        s = SCENARIOS.get(r["slug"])
        r["title"], r["engine"] = (s["title"], s["engine"]) if s else (r["slug"], "?")
        r.pop("score_detail", None)
    return rows


@app.get("/api/leaderboard")
def leaderboard(engine: str = "all", period: str = "all"):
    if engine != "all" and engine not in ENGINES:
        raise HTTPException(404, "no such track")
    slugs = None if engine == "all" else [s["slug"] for s in SCENARIOS.values() if s["engine"] == engine]
    since = int(time.time()) - 30 * 86400 if period == "30d" else None
    return store.leaderboard(slugs, since)


@app.get("/api/scoring")
def scoring_rules():
    return scoring.RULES | {"max_total": sum(scoring.max_points(s["difficulty"]) for s in SCENARIOS.values())}


# ---------------------------------------------------------------- sandboxes

class StartReq(BaseModel):
    slug: str


@app.post("/api/sessions")
def start_session(req: StartReq, u: dict = Depends(require_user)):
    scenario(req.slug)
    image = f"saddb/{req.slug}:latest"
    try:
        labels = dk.images.get(image).labels or {}
    except ImageNotFound:
        raise HTTPException(503, f"image {image} is not built; run bin/sadb build {req.slug}")
    with _start_lock:
        mine = user_boxes(u["id"])
        if mine:
            raise HTTPException(409, f"you already have a box running ({mine[0].labels['saddb.slug']}); end it first")
        if len(dk.containers.list(filters={"label": LABEL})) >= config.MAX_SESSIONS:
            raise HTTPException(429, f"all {config.MAX_SESSIONS} sandboxes are busy; try again in a few minutes")
        sid = secrets.token_hex(12)
        expires = int(time.time()) + box_seconds(SCENARIOS[req.slug])
        mem = labels.get("saddb.mem", "512m")
        store.start_attempt(u["id"], req.slug, sid, expires)
        ceiling = expires + config.MAX_EXTENSIONS * config.EXTEND_SECONDS   # label = hard max; DB holds the live expiry
        c = _run_box(image, req.slug, sid, u["id"], ceiling, mem)
    return session_info(c)


def _run_box(image: str, slug: str, sid: str, uid: int, expires: int, mem: str):
    req_slug = slug
    return dk.containers.run(
        image, detach=True,
        name=f"saddb-{req_slug}-{sid[:6]}", hostname=f"sad-{req_slug}"[:63],
        labels={LABEL: sid, "saddb.slug": req_slug, "saddb.owner": str(uid), "saddb.expires": str(expires)},
        network_mode="none",           # no way in or out except docker exec
        mem_limit=mem, memswap_limit=mem, nano_cpus=1_000_000_000, pids_limit=256,
        init=True, security_opt=["no-new-privileges"],
        cap_drop=["NET_RAW", "MKNOD", "AUDIT_WRITE", "SYS_CHROOT", "SETFCAP", "NET_BIND_SERVICE"],
    )


@app.get("/api/sessions/{sid}")
def get_session(sid: str, u: dict = Depends(require_user)):
    c = find(sid, u)
    ready = c.status == "running" and c.exec_run(["test", "-f", "/run/sad-ready"]).exit_code == 0
    return session_info(c) | {"ready": ready}


@app.post("/api/sessions/{sid}/extend")
def extend_session(sid: str, u: dict = Depends(require_user)):
    c = find(sid, u)
    r = store.extend_box(sid, config.EXTEND_SECONDS, config.MAX_EXTENSIONS)
    if not r["extended"]:
        raise HTTPException(409, f"no extensions left (max {config.MAX_EXTENSIONS})")
    return session_info(c)


@app.post("/api/sessions/{sid}/check")
def check_session(sid: str, u: dict = Depends(require_user)):
    c = find(sid, u)
    r = c.exec_run(["timeout", "90", "/opt/sad/check.sh"], user="root")
    passed = r.exit_code == 0
    rec = store.record_check(sid, passed, scorer_for(c.labels["saddb.slug"]))
    return {"passed": passed, "output": r.output.decode(errors="replace").strip(), "seconds": rec.get("seconds"),
            "score": rec.get("score"), "previous_best": rec.get("previous_best")}


@app.delete("/api/sessions/{sid}")
def end_session(sid: str, u: dict = Depends(require_user)):
    find(sid, u).remove(force=True, v=True)
    store.end_attempt(sid, "ended")
    return {"ok": True}


@app.websocket("/api/sessions/{sid}/tty")
async def tty(ws: WebSocket, sid: str):
    origin = ws.headers.get("origin", "")
    host = ws.headers.get("host", "")
    await ws.accept()
    try:
        if origin.split("://", 1)[-1] != host:
            raise HTTPException(403, "cross-site terminal request refused")
        uid = ws.session.get("uid")
        user = store.get_user(uid) if uid else None
        if not user:
            raise HTTPException(401, "sign in first")
        c = find(sid, user)
    except HTTPException as e:
        await ws.send_text(f"\r\n\x1b[31m{e.detail}\x1b[0m\r\n")
        await ws.close()
        return
    cfg = c.attrs["Config"]["Labels"]
    api = dk.api
    ex = api.exec_create(c.id, ["bash", "-l"], stdin=True, tty=True, user=cfg.get("saddb.user", "postgres"),
                         workdir=cfg.get("saddb.home", "/"), environment={"TERM": "xterm-256color"})
    raw = api.exec_start(ex["Id"], socket=True, tty=True)._sock
    raw.setblocking(True)
    loop = asyncio.get_running_loop()

    async def pump_out():
        while True:
            data = await loop.run_in_executor(None, raw.recv, 4096)
            if not data:
                break
            await ws.send_bytes(data)

    reader = asyncio.create_task(pump_out())
    try:
        while not reader.done():
            recv = asyncio.create_task(ws.receive())
            done, _ = await asyncio.wait({recv, reader}, return_when=asyncio.FIRST_COMPLETED)
            if recv not in done:
                recv.cancel()
                break
            msg = recv.result()
            if msg["type"] == "websocket.disconnect":
                break
            if msg.get("bytes"):
                await loop.run_in_executor(None, raw.sendall, msg["bytes"])
            elif msg.get("text"):
                t = msg["text"]
                if t.startswith("\x00resize:"):           # control message: \0resize:<cols>x<rows>
                    try:
                        cols, rows = (int(v) for v in t[8:].split("x"))
                        api.exec_resize(ex["Id"], height=rows, width=cols)
                    except (ValueError, APIError):
                        pass
                else:
                    await loop.run_in_executor(None, raw.sendall, t.encode())
    except WebSocketDisconnect:
        pass
    finally:
        try:
            raw.sendall(b"\x04exit\n")
        except OSError:
            pass
        raw.close()
        reader.cancel()
        try:
            await ws.close()
        except RuntimeError:
            pass


app.mount("/static", StaticFiles(directory=STATIC), name="static")


@app.get("/{path:path}")
def spa(path: str):
    return FileResponse(STATIC / "index.html")
