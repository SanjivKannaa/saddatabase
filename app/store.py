"""SQLite store: users, per-scenario progress and every attempt (one per sandbox session)."""
import sqlite3
import time
from contextlib import contextmanager

from .config import DB_PATH

SCHEMA = """
create table if not exists users (
  id integer primary key,
  google_sub text unique,
  email text not null unique,
  name text, picture text,
  created_at integer not null, last_login_at integer
);
create table if not exists progress (
  user_id integer not null references users(id),
  slug text not null,
  hints_revealed integer not null default 0,
  solution_viewed integer not null default 0,
  first_solved_at integer, best_seconds integer,
  attempts integer not null default 0, solves integer not null default 0,
  primary key (user_id, slug)
);
create table if not exists attempts (
  id integer primary key,
  user_id integer not null references users(id),
  slug text not null,
  session_id text not null unique,
  started_at integer not null, ended_at integer, end_reason text,
  checks integer not null default 0,
  hints_used integer not null default 0,
  solution_viewed integer not null default 0,
  solved_at integer
);
create index if not exists attempts_user on attempts (user_id, started_at desc);
"""


def init() -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    with db() as c:
        c.execute("pragma journal_mode = wal")
        c.executescript(SCHEMA)


@contextmanager
def db():
    c = sqlite3.connect(DB_PATH, timeout=10)
    c.row_factory = sqlite3.Row
    c.execute("pragma foreign_keys = on")
    try:
        yield c
        c.commit()
    finally:
        c.close()


def now() -> int:
    return int(time.time())


def upsert_google_user(sub: str, email: str, name: str, picture: str) -> int:
    with db() as c:
        row = c.execute("select id from users where google_sub = ? or email = ?", (sub, email.lower())).fetchone()
        if row:
            c.execute("update users set google_sub=?, email=?, name=?, picture=?, last_login_at=? where id=?",
                      (sub, email.lower(), name, picture, now(), row["id"]))
            return row["id"]
        return c.execute("insert into users (google_sub, email, name, picture, created_at, last_login_at) values (?,?,?,?,?,?)",
                         (sub, email.lower(), name, picture, now(), now())).lastrowid


def get_user(uid: int):
    with db() as c:
        r = c.execute("select id, email, name, picture, created_at from users where id=?", (uid,)).fetchone()
        return dict(r) if r else None


def _ensure_progress(c, uid: int, slug: str) -> None:
    c.execute("insert or ignore into progress (user_id, slug) values (?, ?)", (uid, slug))


def start_attempt(uid: int, slug: str, sid: str) -> None:
    with db() as c:
        _ensure_progress(c, uid, slug)
        c.execute("update progress set attempts = attempts + 1 where user_id=? and slug=?", (uid, slug))
        c.execute("insert into attempts (user_id, slug, session_id, started_at) values (?,?,?,?)", (uid, slug, sid, now()))


def end_attempt(sid: str, reason: str) -> None:
    with db() as c:
        c.execute("update attempts set ended_at=?, end_reason=? where session_id=? and ended_at is null", (now(), reason, sid))


def open_session_ids() -> list[str]:
    with db() as c:
        return [r[0] for r in c.execute("select session_id from attempts where ended_at is null")]


def record_check(sid: str, passed: bool) -> dict:
    """Count a check; on the first pass of this attempt, mark it solved and update progress."""
    with db() as c:
        a = c.execute("select * from attempts where session_id=?", (sid,)).fetchone()
        if not a:
            return {}
        c.execute("update attempts set checks = checks + 1 where id=?", (a["id"],))
        if not passed or a["solved_at"]:
            return {"seconds": (a["solved_at"] - a["started_at"]) if a["solved_at"] else None}
        t = now()
        secs = t - a["started_at"]
        c.execute("update attempts set solved_at=? where id=?", (t, a["id"]))
        c.execute("""update progress set solves = solves + 1,
                       first_solved_at = coalesce(first_solved_at, ?),
                       best_seconds = min(coalesce(best_seconds, ?), ?)
                     where user_id=? and slug=?""", (t, secs, secs, a["user_id"], a["slug"]))
        return {"seconds": secs, "first": True}


def reveal(uid: int, slug: str, hints_total: int, solution: bool = False) -> dict:
    with db() as c:
        _ensure_progress(c, uid, slug)
        p = c.execute("select * from progress where user_id=? and slug=?", (uid, slug)).fetchone()
        n, sol = p["hints_revealed"], p["solution_viewed"]
        if solution:
            sol = 1
        elif n < hints_total:
            n += 1
        c.execute("update progress set hints_revealed=?, solution_viewed=? where user_id=? and slug=?", (n, sol, uid, slug))
        # attribute to the open attempt, if any
        col = "solution_viewed = 1" if solution else "hints_used = max(hints_used, ?)"
        args = () if solution else (n,)
        c.execute(f"update attempts set {col} where id = (select id from attempts where user_id=? and slug=? and ended_at is null order by started_at desc limit 1)",
                  (*args, uid, slug))
        return {"hints_revealed": n, "solution_viewed": bool(sol)}


def progress_for(uid: int) -> dict[str, dict]:
    with db() as c:
        return {r["slug"]: dict(r) for r in c.execute("select * from progress where user_id=?", (uid,))}


def history(uid: int, limit: int = 50) -> list[dict]:
    with db() as c:
        return [dict(r) for r in c.execute(
            "select slug, started_at, ended_at, end_reason, checks, hints_used, solution_viewed, solved_at from attempts where user_id=? order by started_at desc limit ?",
            (uid, limit))]


def leaderboard(limit: int = 50) -> list[dict]:
    with db() as c:
        return [dict(r) for r in c.execute("""
            select u.id, u.name, u.picture,
                   count(p.first_solved_at) as solved,
                   sum(case when p.first_solved_at is not null and p.solution_viewed = 0 then 1 else 0 end) as solved_clean,
                   coalesce(sum(p.best_seconds), 0) as total_seconds,
                   max(p.first_solved_at) as last_solved_at
            from users u join progress p on p.user_id = u.id
            group by u.id having solved > 0
            order by solved_clean desc, solved desc, total_seconds asc limit ?""", (limit,))]
