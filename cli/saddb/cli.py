"""saddb: sadDatabase in your terminal.

Each scenario is a Docker image with a broken database. `saddb start <slug>` boots it (no network), shows the task
and drops you into its shell; `saddb check` runs the grader. Progress and points live in ~/.local/share/saddb/.
Only needs Docker; no account, no server.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import textwrap
import time
from importlib import resources
from pathlib import Path

from . import __version__, scoring

REGISTRY = os.environ.get("SADDB_REGISTRY", "ghcr.io/sanjivkannaa")
BOX_SECONDS = int(os.environ.get("SADDB_BOX_MINUTES", "15")) * 60
EXTEND_SECONDS = int(os.environ.get("SADDB_EXTEND_MINUTES", "15")) * 60
MAX_EXTENSIONS = int(os.environ.get("SADDB_MAX_EXTENSIONS", "2"))
DATA = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")) / "saddb"
STATE = DATA / "state.json"
LABEL = "saddb.cli"

CATALOG = json.loads(resources.files("saddb").joinpath("catalog.json").read_text())
ENGINES = CATALOG["engines"]
SCEN = {s["slug"]: s for s in CATALOG["scenarios"]}

# ------------------------------------------------------------------ output

COLOR = sys.stdout.isatty() and "NO_COLOR" not in os.environ


def c(code: str, s: str) -> str:
    return f"\033[{code}m{s}\033[0m" if COLOR else s


bold = lambda s: c("1", s)          # noqa: E731
dim = lambda s: c("2", s)           # noqa: E731
red = lambda s: c("31", s)          # noqa: E731
green = lambda s: c("32", s)        # noqa: E731
yellow = lambda s: c("33", s)       # noqa: E731
cyan = lambda s: c("36", s)         # noqa: E731
DIFF = {"easy": green, "medium": yellow, "hard": red}


def die(msg: str, code: int = 1):
    print(red("✗ ") + msg, file=sys.stderr)
    sys.exit(code)


def inline(s: str) -> str:
    s = re.sub(r"\*\*(.+?)\*\*", lambda m: bold(m.group(1)), s)
    s = re.sub(r"`([^`]+)`", lambda m: cyan(m.group(1)), s)
    return s.replace("\\\\", "\\")


def md(text: str, indent: str = "  ") -> str:
    """Just enough markdown for task text: paragraphs, lists, fenced code, **bold**, `code`."""
    width = min(100, shutil.get_terminal_size((100, 20)).columns) - len(indent) - 2
    out, para, code = [], [], False

    def flush():
        if para:
            text = inline(" ".join(para))           # style first, so markup that wraps still closes
            out.extend(indent + l for l in _wrap(text, width))
            para.clear()

    for line in text.strip("\n").split("\n"):
        if line.strip().startswith("```"):
            flush()
            code = not code
            continue
        if code:
            out.append(indent + "  " + cyan(line))
        elif not line.strip():
            flush()
            out.append("")
        elif re.match(r"\s*(\d+\.|[-*]) ", line):
            flush()
            m = re.match(r"(\s*(?:\d+\.|[-*]) )(.*)", line)
            sub = _wrap(inline(m.group(2)), width - len(m.group(1))) or [""]
            out.append(indent + m.group(1) + sub[0])
            out.extend(indent + " " * len(m.group(1)) + l for l in sub[1:])
        elif out and para == [] and re.match(r"\s{2,}\S", line) and out[-1].strip():
            out.append(indent + line)          # continuation of a list item
        else:
            para.append(line.strip())
    flush()
    return "\n".join(l if "\033[" in l else inline(l) for l in out)


ANSI = re.compile(r"\033\[[0-9;]*m")


def _wrap(text: str, width: int) -> list[str]:
    """textwrap that ignores ANSI codes when measuring."""
    words, lines, cur, n = text.split(" "), [], [], 0
    for w in words:
        wl = len(ANSI.sub("", w))
        if cur and n + 1 + wl > width:
            lines.append(" ".join(cur)); cur, n = [], 0
        cur.append(w); n += wl + (1 if n else 0)
    if cur:
        lines.append(" ".join(cur))
    return lines


def dur(s) -> str:
    if s is None:
        return "–"
    s = int(s)
    return f"{s}s" if s < 60 else f"{s // 60}m {s % 60:02d}s" if s < 3600 else f"{s // 3600}h {s % 3600 // 60}m"


# ------------------------------------------------------------------ state

def load() -> dict:
    try:
        st = json.loads(STATE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        st = {}
    st.setdefault("progress", {})
    st.setdefault("history", [])
    st.setdefault("active", None)
    return st


def save(st: dict) -> None:
    DATA.mkdir(parents=True, exist_ok=True)
    tmp = STATE.with_suffix(".tmp")
    tmp.write_text(json.dumps(st, indent=1))
    tmp.replace(STATE)


def prog(st: dict, slug: str) -> dict:
    return st["progress"].setdefault(slug, {"hints_revealed": 0, "solution_viewed": False, "best_score": None,
                                            "best_seconds": None, "attempts": 0, "solves": 0})


def total_points(st: dict) -> int:
    return sum(p.get("best_score") or 0 for p in st["progress"].values())


# ------------------------------------------------------------------ docker

def docker(*args, capture=True, check=True, quiet=False) -> subprocess.CompletedProcess:
    try:
        r = subprocess.run(["docker", *args], text=True, capture_output=capture)
    except FileNotFoundError:
        die("docker is not installed (or not on PATH). saddb needs Docker: https://docs.docker.com/get-docker/")
    if check and r.returncode != 0:
        if quiet:
            return r
        err = (r.stderr or "").strip()
        if "permission denied" in err and "docker.sock" in err:
            die("can't talk to Docker: add yourself to the docker group (then log in again), or run Docker Desktop.")
        die(f"docker {args[0]} failed: {err[:400]}")
    return r


def image_for(slug: str) -> str:
    """Local saddb/<slug> image if present, else pull it from the registry and tag it locally."""
    local = f"saddb/{slug}:latest"
    if docker("image", "inspect", local, check=False).returncode == 0:
        return local
    remote = f"{REGISTRY}/saddb-{slug}:latest"
    print(dim(f"pulling {remote} (first time only; database images are 0.3–1.5 GB)…"))
    if docker("pull", remote, capture=False, check=False).returncode != 0:
        die(f"couldn't get the image for {slug}.\n"
            f"  • If the registry is private: docker login {REGISTRY.split('/')[0]}\n"
            f"  • Or build locally from the repo: git clone https://github.com/SanjivKannaa/saddatabase && "
            f"cd saddatabase && bin/sadb build {slug}")
    docker("tag", remote, local)
    return local


def labels(image: str) -> dict:
    out = docker("image", "inspect", "-f", "{{json .Config.Labels}}", image).stdout
    return json.loads(out) or {}


def running_box():
    """(container id, labels) of the running saddb box, or None."""
    out = docker("ps", "-q", "--filter", f"label={LABEL}=1").stdout.split()
    if not out:
        return None
    lab = json.loads(docker("inspect", "-f", "{{json .Config.Labels}}", out[0]).stdout)
    return out[0], lab


def box_alive(cid: str) -> bool:
    r = docker("inspect", "-f", "{{.State.Running}}", cid, check=False)
    return r.returncode == 0 and r.stdout.strip() == "true"


def set_expiry(cid: str, ts: int) -> None:
    docker("exec", "-u", "root", cid, "sh", "-c", f"echo {ts} > /run/sad-expires")


# The box times itself out: a root-only loop inside it stops PID 1 at the deadline (works with no saddb running).
WATCHER = 'while :; do e=$(cat /run/sad-expires 2>/dev/null || echo 0); [ "$(date +%s)" -ge "$e" ] && kill -TERM 1; sleep 5; done'
# Shown in the player's prompt in the last 3 minutes.
PROMPT = ('e=$(cat /run/sad-expires 2>/dev/null); if [ -n "$e" ]; then l=$((e-$(date +%s))); '
          'if [ $l -le 180 ]; then printf "\\033[31m⏱  %dm%02ds left (saddb extend on your machine)\\033[0m\\n" $((l/60)) $((l%60)); fi; fi')


def active(st: dict, need: bool = True):
    """Return the active box from state, reconciling it with Docker (expired / removed boxes end the attempt)."""
    a = st.get("active")
    if a and not box_alive(a["container"]):
        h = next((h for h in reversed(st["history"]) if h.get("container") == a["container"]), None)
        if h and not h.get("ended_at"):
            h["ended_at"] = int(time.time())
            h["end_reason"] = "expired" if time.time() >= a["expires_at"] else "gone"
        st["active"] = None
        save(st)
        if need:
            die(f"your {a['slug']} box is gone ({'time ran out' if time.time() >= a['expires_at'] else 'it was removed'}). "
                f"Start again with: saddb start {a['slug']}")
        return None
    if not a and need:
        die("no box running. Start one with: saddb start <scenario>   (see: saddb list)")
    return a


# ------------------------------------------------------------------ commands

def cmd_list(args):
    st = load()
    for key, e in ENGINES.items():
        if args.track and args.track not in (key, e["name"].lower()):
            continue
        items = [s for s in CATALOG["scenarios"] if s["engine"] == key]
        got = sum(prog(st, s["slug"]).get("best_score") or 0 for s in items if s["slug"] in st["progress"])
        mx = sum(scoring.max_points(s["difficulty"]) for s in items)
        done = sum(1 for s in items if (st["progress"].get(s["slug"]) or {}).get("solves"))
        print(f"\n{bold(e['name'] + ' ' + e['version'])}  {dim(f'{done}/{len(items)} solved · {got}/{mx} pts')}")
        for i, s in enumerate(items, 1):
            p = st["progress"].get(s["slug"]) or {}
            mark = green("✓") if p.get("solves") else yellow("•") if p.get("attempts") else " "
            pts = f"{p['best_score']}/{scoring.max_points(s['difficulty'])}" if p.get("solves") else f"≤{scoring.max_points(s['difficulty'])}"
            print(f"  {mark} {i}. {s['slug']:<26} {DIFF[s['difficulty']](s['difficulty']):<17} {s['title']:<44} {dim(pts + ' pts')}")
    print(dim("\nsaddb start <scenario> to play · saddb show <scenario> to read the task first"))


def cmd_show(args):
    s = SCEN.get(args.slug) or die(f"no scenario {args.slug!r} (see: saddb list)")
    task(s)


def task(s: dict):
    e = ENGINES[s["engine"]]
    print(f"\n{bold(s['title'])}  {dim('·')} {DIFF[s['difficulty']](s['difficulty'])} {dim('·')} ~{s['minutes']} min "
          f"{dim('·')} {e['name']} {e['version']} {dim('·')} up to {scoring.max_points(s['difficulty'])} pts\n")
    print(md(s["description"]))
    print()


def cmd_start(args):
    s = SCEN.get(args.slug) or die(f"no scenario {args.slug!r} (see: saddb list)")
    st = load()
    a = active(st, need=False)
    if a:
        if a["slug"] == s["slug"]:
            print(dim(f"your {s['slug']} box is already running; reattaching."))
            return cmd_shell(args) if not args.detach else None
        if not args.force:
            die(f"you already have a {a['slug']} box running. End it first (saddb end), or use --force.")
        end_box(st, "replaced")
    stray = running_box()
    if stray:
        docker("rm", "-f", stray[0], check=False)

    image = image_for(s["slug"])
    lab = labels(image)
    now = int(time.time())
    expires = now + BOX_SECONDS
    print(dim(f"booting your broken {ENGINES[s['engine']]['name']} box…"), end="", flush=True)
    cid = docker("run", "-d", "--rm", "--init", "--network", "none",
                 "--memory", lab.get("saddb.mem", "512m"), "--memory-swap", lab.get("saddb.mem", "512m"),
                 "--cpus", "1", "--pids-limit", "256", "--security-opt", "no-new-privileges",
                 "--cap-drop", "NET_RAW", "--cap-drop", "MKNOD", "--cap-drop", "AUDIT_WRITE",
                 "--hostname", f"sad-{s['slug']}"[:63], "--name", f"saddb-{s['slug']}-{now}",
                 "--label", f"{LABEL}=1", "--label", f"saddb.cli.slug={s['slug']}", image).stdout.strip()
    for _ in range(240):
        if docker("exec", cid, "test", "-f", "/run/sad-ready", check=False).returncode == 0:
            break
        time.sleep(0.5)
    else:
        docker("rm", "-f", cid, check=False)
        die("the box didn't come up in 2 minutes")
    set_expiry(cid, expires)
    docker("exec", "-d", "-u", "root", cid, "sh", "-c", WATCHER)
    print(green(" ready"))

    p = prog(st, s["slug"])
    p["attempts"] += 1
    st["active"] = {"slug": s["slug"], "container": cid, "started_at": now, "expires_at": expires,
                    "extensions": 0, "checks": 0, "user": lab.get("saddb.user", "root"), "home": lab.get("saddb.home", "/")}
    st["history"].append({"slug": s["slug"], "container": cid, "started_at": now, "checks": 0, "solved_at": None,
                          "score": None, "ended_at": None})
    save(st)
    task(s)
    print(dim(f"Box lives {BOX_SECONDS // 60} min (saddb extend: +{EXTEND_SECONDS // 60} min, {MAX_EXTENSIONS}x). "
              f"Exit the shell any time; the box keeps running. Then: saddb check · saddb hint · saddb shell · saddb end"))
    if not args.detach:
        input(dim("Press Enter to open the shell… "))
        shell(st["active"])
        after_shell()


def shell(a: dict):
    tty = ["-it"] if sys.stdin.isatty() else ["-i"]
    subprocess.run(["docker", "exec", *tty, "-u", a["user"], "-w", a["home"], "-e", "TERM=" + os.environ.get("TERM", "xterm-256color"),
                    "-e", f"PROMPT_COMMAND={PROMPT}", a["container"], "bash", "-l"])


def after_shell():
    st = load()
    a = active(st, need=False)
    if a:
        print(dim(f"\nleft the shell; the box is still running ({dur(a['expires_at'] - time.time())} left).") +
              f"\n  {bold('saddb check')} grade it · {bold('saddb shell')} go back · {bold('saddb hint')} · {bold('saddb end')}")


def cmd_shell(args):
    st = load()
    a = active(st)
    shell(a)
    after_shell()


def cmd_task(args):
    st = load()
    a = active(st)
    task(SCEN[a["slug"]])
    print(dim(f"{dur(a['expires_at'] - time.time())} left · {MAX_EXTENSIONS - a['extensions']} extension(s) left"))


def cmd_status(args):
    st = load()
    a = active(st, need=False)
    if not a:
        print("no box running.  " + dim(f"{total_points(st)} pts so far · saddb list"))
        return
    s = SCEN[a["slug"]]
    print(f"{bold(s['title'])} ({a['slug']})  {dim('·')}  {dur(a['expires_at'] - time.time())} left  {dim('·')}  "
          f"{MAX_EXTENSIONS - a['extensions']} extension(s) left  {dim('·')}  {a['checks']} check(s)")


def cmd_check(args):
    st = load()
    a = active(st)
    s = SCEN[a["slug"]]
    print(dim("grading…"))
    r = docker("exec", "-u", "root", a["container"], "timeout", "90", "/opt/sad/check.sh", check=False)
    out = (r.stdout + r.stderr).strip()
    passed = r.returncode == 0
    a["checks"] += 1
    h = next(h for h in reversed(st["history"]) if h["container"] == a["container"])
    h["checks"] = a["checks"]
    for line in out.splitlines():
        print("  " + (green(line) if line.startswith("PASS") else red(line) if line.startswith("FAIL") else line))
    if not passed:
        save(st)
        print(dim("\nnot yet. saddb shell to keep going, saddb hint if you're stuck."))
        return
    if h.get("solved_at"):
        save(st)
        print(green("\nstill solved ✓") + dim(f" ({h['score']} pts, already recorded)"))
        return
    now = int(time.time())
    secs = now - a["started_at"]
    p = prog(st, a["slug"])
    sc = scoring.compute(s["difficulty"], s.get("minutes", 15), secs, p["hints_revealed"], p["solution_viewed"], a["checks"])
    prev = p.get("best_score")
    h.update(solved_at=now, score=sc["total"])
    p["solves"] += 1
    p["best_score"] = max(prev or 0, sc["total"])
    p["best_seconds"] = min(p["best_seconds"] or secs, secs)
    p.setdefault("first_solved_at", now)
    save(st)
    print(green(f"\n🎉 solved in {dur(secs)}"))
    for label, v in sc["parts"]:
        print(f"   {label:<44} {('+' if v > 0 else '') + str(v):>6}")
    print(f"   {bold('this solve'):<44} {bold(str(sc['total']) + ' pts'):>6}")
    if prev is not None:
        print(dim(f"   best for this scenario: {p['best_score']} pts"))
    print(dim(f"   total: {total_points(st)} pts"))
    track = [x for x in CATALOG["scenarios"] if x["engine"] == s["engine"]]
    i = [x["slug"] for x in track].index(s["slug"])
    nxt = track[i + 1]["slug"] if i + 1 < len(track) else None
    print(f"\n{'next in track: ' + bold('saddb start ' + nxt) if nxt else 'track complete! ' + dim('saddb list for the others')}"
          f"{dim('  ·  saddb end to remove this box')}")


def cmd_hint(args):
    st = load()
    slug = args.slug or (st.get("active") or {}).get("slug") or die("which scenario? saddb hint <scenario>")
    s = SCEN.get(slug) or die(f"no scenario {slug!r}")
    p = prog(st, slug)
    hints = s["hints"]
    cost = round(scoring.BASE[s["difficulty"]] * scoring.HINT_PENALTY)
    if p["hints_revealed"] < len(hints) and not args.again:
        if not p.get("solves") and not confirm(f"Hint {p['hints_revealed'] + 1}/{len(hints)} costs {cost} pts on this scenario. Show it?"):
            return
        p["hints_revealed"] += 1
        save(st)
    if not p["hints_revealed"]:
        print(dim("no hints shown yet."))
    for i, h in enumerate(hints[:p["hints_revealed"]], 1):
        print(f"\n {yellow(f'hint {i}/{len(hints)}')}\n{md(h, '   ')}")
    if p["hints_revealed"] >= len(hints):
        print(dim("\nthat's all the hints. saddb solution if you're truly stuck (scores 0 if unsolved)."))
    print()


def cmd_solution(args):
    st = load()
    slug = args.slug or (st.get("active") or {}).get("slug") or die("which scenario? saddb solution <scenario>")
    s = SCEN.get(slug) or die(f"no scenario {slug!r}")
    p = prog(st, slug)
    if not p.get("solves") and not p["solution_viewed"]:
        if not confirm("You haven't solved this yet: viewing the solution means it scores 0 points. Show it?"):
            return
        p["solution_viewed"] = True
        save(st)
    print(f"\n{bold('Solution & lesson')}\n\n{md(s['solution'])}\n")


def cmd_extend(args):
    st = load()
    a = active(st)
    if a["extensions"] >= MAX_EXTENSIONS:
        die(f"no extensions left (max {MAX_EXTENSIONS}). The box ends in {dur(a['expires_at'] - time.time())}.")
    a["extensions"] += 1
    a["expires_at"] += EXTEND_SECONDS
    set_expiry(a["container"], a["expires_at"])
    save(st)
    print(green(f"+{EXTEND_SECONDS // 60} min") + f": {dur(a['expires_at'] - time.time())} left, "
          f"{MAX_EXTENSIONS - a['extensions']} extension(s) left")


def end_box(st: dict, reason: str):
    a = st.get("active")
    if not a:
        return
    docker("rm", "-f", a["container"], check=False)
    h = next((h for h in reversed(st["history"]) if h["container"] == a["container"]), None)
    if h and not h.get("ended_at"):
        h["ended_at"] = int(time.time())
        h["end_reason"] = reason
    st["active"] = None
    save(st)


def cmd_end(args):
    st = load()
    a = active(st)
    end_box(st, "ended")
    print(f"removed your {a['slug']} box.")


def cmd_progress(args):
    st = load()
    solved = [k for k, p in st["progress"].items() if p.get("solves")]
    mx = sum(scoring.max_points(s["difficulty"]) for s in CATALOG["scenarios"])
    print(f"\n{bold(str(total_points(st)))} / {mx} pts  {dim('·')}  {len(solved)}/{len(SCEN)} solved  {dim('·')}  "
          f"{len(st['history'])} box{'es' if len(st['history']) != 1 else ''} started  {dim('·')}  {sum(1 for p in st['progress'].values() if p.get('solution_viewed'))} solutions viewed\n")
    for key, e in ENGINES.items():
        items = [s for s in CATALOG["scenarios"] if s["engine"] == key]
        got = sum((st["progress"].get(s["slug"]) or {}).get("best_score") or 0 for s in items)
        tmax = sum(scoring.max_points(s["difficulty"]) for s in items)
        done = sum(1 for s in items if (st["progress"].get(s["slug"]) or {}).get("solves"))
        bar = "█" * round(20 * done / len(items)) + "░" * (20 - round(20 * done / len(items)))
        print(f"  {e['name']:<11} {green(bar)} {done}/{len(items)}  {dim(f'{got}/{tmax} pts')}")
    if st["history"]:
        print(f"\n{bold('recent')}")
        for h in st["history"][-10:][::-1]:
            res = green("✓ " + dur(h["solved_at"] - h["started_at"])) if h.get("solved_at") else dim(h.get("end_reason") or "running")
            pts = f"{h['score']} pts" if h.get("score") is not None else ""
            print(f"  {time.strftime('%b %d %H:%M', time.localtime(h['started_at']))}  {h['slug']:<26} {res:<20} {dim(pts)}")
    print(dim(f"\nprogress file: {STATE}"))


def confirm(q: str) -> bool:
    if "--yes" in sys.argv or "-y" in sys.argv:
        return True
    if not sys.stdin.isatty():
        print(dim(q + " (non-interactive: use --yes)"))
        return "--yes" in sys.argv or "-y" in sys.argv
    if "--yes" in sys.argv or "-y" in sys.argv:
        return True
    return input(f"{q} [y/N] ").strip().lower() in ("y", "yes")


def main(argv=None):
    ap = argparse.ArgumentParser(prog="saddb", description="sadDatabase in your terminal: fix broken databases in local Docker boxes.",
                                 epilog="Typical run: saddb list → saddb start pg-wont-start → (fix it in the shell, exit) → saddb check")
    ap.add_argument("--version", action="version", version=f"saddb {__version__} ({len(SCEN)} scenarios)")
    sub = ap.add_subparsers(dest="cmd", metavar="command")
    p = sub.add_parser("list", help="tracks and scenarios, with your progress"); p.add_argument("track", nargs="?"); p.set_defaults(f=cmd_list)
    p = sub.add_parser("show", help="read a scenario's task without starting it"); p.add_argument("slug"); p.set_defaults(f=cmd_show)
    p = sub.add_parser("start", help="boot a scenario's broken box and open its shell"); p.add_argument("slug")
    p.add_argument("-d", "--detach", action="store_true", help="don't open the shell")
    p.add_argument("--force", action="store_true", help="end your current box first"); p.set_defaults(f=cmd_start)
    sub.add_parser("shell", help="open a shell in your running box").set_defaults(f=cmd_shell)
    sub.add_parser("task", help="show the running scenario's task again").set_defaults(f=cmd_task)
    sub.add_parser("status", help="what's running and how long it has left").set_defaults(f=cmd_status)
    sub.add_parser("check", help="grade your fix").set_defaults(f=cmd_check)
    p = sub.add_parser("hint", help="reveal the next hint (costs points)"); p.add_argument("slug", nargs="?")
    p.add_argument("--again", action="store_true", help="re-show hints you've already seen"); p.add_argument("-y", "--yes", action="store_true")
    p.set_defaults(f=cmd_hint)
    p = sub.add_parser("solution", help="show the solution (0 points if unsolved)"); p.add_argument("slug", nargs="?")
    p.add_argument("-y", "--yes", action="store_true"); p.set_defaults(f=cmd_solution)
    sub.add_parser("extend", help=f"add {EXTEND_SECONDS // 60} min to your box (max {MAX_EXTENSIONS}x)").set_defaults(f=cmd_extend)
    sub.add_parser("end", help="remove your box").set_defaults(f=cmd_end)
    sub.add_parser("progress", help="points, per-track progress and history").set_defaults(f=cmd_progress)
    args = ap.parse_args(argv)
    if not getattr(args, "f", None):
        ap.print_help()
        return
    try:
        args.f(args)
    except KeyboardInterrupt:
        print()
        sys.exit(130)


if __name__ == "__main__":
    main()
