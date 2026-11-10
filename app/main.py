"""sadDatabase: each session is a disposable, network-less container with a broken database."""
import asyncio
import os
import secrets
import time
import tomllib
from pathlib import Path

import docker
from docker.errors import APIError, ImageNotFound, NotFound
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

ROOT = Path(__file__).resolve().parent.parent
SCENARIOS_DIR = ROOT / "scenarios"
STATIC = Path(__file__).resolve().parent / "static"
SESSION_TTL = int(os.getenv("SADDB_SESSION_MINUTES", "45")) * 60
MAX_SESSIONS = int(os.getenv("SADDB_MAX_SESSIONS", "4"))
LABEL = "saddb.session"

dk = docker.from_env()
app = FastAPI(title="sadDatabase")


def load_scenarios() -> dict[str, dict]:
    out = {}
    for f in sorted(SCENARIOS_DIR.glob("*/scenario.toml")):
        meta = tomllib.loads(f.read_text())
        meta["slug"] = f.parent.name
        out[meta["slug"]] = meta
    return dict(sorted(out.items(), key=lambda kv: kv[1].get("order", 99)))


SCENARIOS = load_scenarios()


def public(meta: dict, full: bool = False) -> dict:
    keys = ["slug", "title", "difficulty", "minutes", "tags", "summary"]
    if full:
        keys += ["description", "hints", "solution"]
    return {k: meta.get(k) for k in keys} | {"engine": "PostgreSQL 17"}


def find(sid: str):
    if not sid.isalnum():
        raise HTTPException(404, "no such session")
    cs = dk.containers.list(all=True, filters={"label": f"{LABEL}={sid}"})
    if not cs:
        raise HTTPException(404, "session expired or not found")
    return cs[0]


def session_info(c) -> dict:
    return {
        "id": c.labels[LABEL],
        "slug": c.labels["saddb.slug"],
        "expires_at": int(c.labels["saddb.expires"]),
        "status": c.status,
    }


@app.get("/api/scenarios")
def list_scenarios():
    return [public(m) for m in SCENARIOS.values()]


@app.get("/api/scenarios/{slug}")
def get_scenario(slug: str):
    if slug not in SCENARIOS:
        raise HTTPException(404, "no such scenario")
    return public(SCENARIOS[slug], full=True)


class StartReq(BaseModel):
    slug: str


@app.post("/api/sessions")
def start_session(req: StartReq):
    if req.slug not in SCENARIOS:
        raise HTTPException(404, "no such scenario")
    running = dk.containers.list(filters={"label": LABEL})
    if len(running) >= MAX_SESSIONS:
        raise HTTPException(429, f"all {MAX_SESSIONS} sandboxes are busy; end one or try again later")
    sid = secrets.token_hex(12)
    expires = int(time.time()) + SESSION_TTL
    try:
        c = dk.containers.run(
            f"saddb/{req.slug}:latest",
            detach=True,
            auto_remove=False,
            name=f"saddb-{req.slug}-{sid[:6]}",
            hostname=f"sad-{req.slug}"[:63],
            labels={LABEL: sid, "saddb.slug": req.slug, "saddb.expires": str(expires)},
            network_mode="none",          # no way in or out except docker exec
            mem_limit="512m",
            memswap_limit="512m",
            nano_cpus=1_000_000_000,
            pids_limit=256,
            init=True,
            security_opt=["no-new-privileges"],
            cap_drop=["NET_RAW", "MKNOD", "AUDIT_WRITE", "SYS_CHROOT", "SETFCAP", "NET_BIND_SERVICE"],
        )
    except ImageNotFound:
        raise HTTPException(503, f"image saddb/{req.slug} not built; run bin/sadb build {req.slug}")
    return session_info(c)


@app.get("/api/sessions/{sid}")
def get_session(sid: str):
    c = find(sid)
    info = session_info(c)
    ready = c.exec_run(["test", "-f", "/run/sad-ready"]).exit_code == 0 if c.status == "running" else False
    return info | {"ready": ready}


@app.post("/api/sessions/{sid}/check")
def check_session(sid: str):
    c = find(sid)
    r = c.exec_run(["timeout", "60", "/opt/sad/check.sh"], user="root")
    out = r.output.decode(errors="replace").strip()
    return {"passed": r.exit_code == 0, "output": out}


@app.delete("/api/sessions/{sid}")
def end_session(sid: str):
    find(sid).remove(force=True)
    return {"ok": True}


@app.websocket("/api/sessions/{sid}/tty")
async def tty(ws: WebSocket, sid: str):
    await ws.accept()
    try:
        c = find(sid)
    except HTTPException as e:
        await ws.send_text(f"\r\n\x1b[31m{e.detail}\x1b[0m\r\n")
        await ws.close()
        return
    api = dk.api
    ex = api.exec_create(c.id, ["bash", "-l"], stdin=True, tty=True, user="postgres",
                         workdir="/var/lib/postgresql", environment={"TERM": "xterm-256color"})
    sock = api.exec_start(ex["Id"], socket=True, tty=True)
    raw = sock._sock
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
                    cols, rows = (int(v) for v in t[8:].split("x"))
                    try:
                        api.exec_resize(ex["Id"], height=rows, width=cols)
                    except APIError:
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


async def reaper():
    while True:
        now = time.time()
        for c in dk.containers.list(all=True, filters={"label": LABEL}):
            if int(c.labels.get("saddb.expires", 0)) < now or c.status == "exited":
                try:
                    c.remove(force=True)
                except (NotFound, APIError):
                    pass
        await asyncio.sleep(30)


@app.on_event("startup")
async def _start_reaper():
    asyncio.create_task(reaper())


app.mount("/static", StaticFiles(directory=STATIC), name="static")


@app.get("/{path:path}")
def spa(path: str):
    return FileResponse(STATIC / "index.html")
