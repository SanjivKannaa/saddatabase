"""SQLite store: users, per-scenario progress and every attempt (one per sandbox session)."""
import json
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


MIGRATIONS = [
    ("attempts", "score", "alter table attempts add column score integer"),
    ("attempts", "score_detail", "alter table attempts add column score_detail text"),
    ("progress", "best_score", "alter table progress add column best_score integer"),
    ("attempts", "expires_at", "alter table attempts add column expires_at integer"),
    ("attempts", "extensions", "alter table attempts add column extensions integer not null default 0"),
]


def init() -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    with db() as c:
        c.execute("pragma journal_mode = wal")
        c.executescript(SCHEMA)
        for table, col, ddl in MIGRATIONS:
            if col not in [r[1] for r in c.execute(f"pragma table_info({table})")]:
                c.execute(ddl)
        c.execute("create index if not exists attempts_solved on attempts (solved_at) where solved_at is not null")


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


def start_attempt(uid: int, slug: str, sid: str, expires_at: int) -> None:
    with db() as c:
        _ensure_progress(c, uid, slug)
        c.execute("update progress set attempts = attempts + 1 where user_id=? and slug=?", (uid, slug))
        c.execute("insert into attempts (user_id, slug, session_id, started_at, expires_at) values (?,?,?,?,?)",
                  (uid, slug, sid, now(), expires_at))


def box_times(sid: str) -> dict | None:
    with db() as c:
        r = c.execute("select expires_at, extensions from attempts where session_id=?", (sid,)).fetchone()
        return dict(r) if r else None


def extend_box(sid: str, add_seconds: int, max_extensions: int) -> dict:
    """Push the expiry of an open box out by add_seconds, at most max_extensions times. Atomic in SQLite."""
    with db() as c:
        cur = c.execute("""update attempts set expires_at = expires_at + ?, extensions = extensions + 1
                           where session_id = ? and ended_at is null and extensions < ?""",
                        (add_seconds, sid, max_extensions))
        r = c.execute("select expires_at, extensions from attempts where session_id=?", (sid,)).fetchone()
        return {"extended": cur.rowcount == 1, **(dict(r) if r else {})}


def end_attempt(sid: str, reason: str) -> None:
    with db() as c:
        c.execute("update attempts set ended_at=?, end_reason=? where session_id=? and ended_at is null", (now(), reason, sid))


def open_session_ids() -> list[str]:
    with db() as c:
        return [r[0] for r in c.execute("select session_id from attempts where ended_at is null")]


def record_check(sid: str, passed: bool, scorer=None) -> dict:
    """Count a check. On the first pass of this attempt, mark it solved, score it and update progress.
    scorer(seconds, hints, peeked, checks) -> {"total", "parts"}."""
    with db() as c:
        a = c.execute("select * from attempts where session_id=?", (sid,)).fetchone()
        if not a:
            return {}
        c.execute("update attempts set checks = checks + 1 where id=?", (a["id"],))
        if not passed or a["solved_at"]:
            return {"seconds": (a["solved_at"] - a["started_at"]) if a["solved_at"] else None,
                    "score": json.loads(a["score_detail"]) if a["score_detail"] else None}
        p = c.execute("select * from progress where user_id=? and slug=?", (a["user_id"], a["slug"])).fetchone()
        prev_best = p["best_score"] if p else None
        t = now()
        secs = t - a["started_at"]
        sc = scorer(secs, p["hints_revealed"] if p else 0, bool(p and p["solution_viewed"]), a["checks"] + 1) if scorer else {"total": 0, "parts": []}
        c.execute("update attempts set solved_at=?, score=?, score_detail=? where id=?", (t, sc["total"], json.dumps(sc), a["id"]))
        c.execute("""update progress set solves = solves + 1,
                       first_solved_at = coalesce(first_solved_at, ?),
                       best_seconds = min(coalesce(best_seconds, ?), ?),
                       best_score = max(coalesce(best_score, 0), ?)
                     where user_id=? and slug=?""", (t, secs, secs, sc["total"], a["user_id"], a["slug"]))
        return {"seconds": secs, "score": sc, "previous_best": prev_best}


def backfill_scores(meta: dict, scorer_for) -> int:
    """Score solved attempts recorded before scoring existed (best effort: uses hints seen so far)."""
    n = 0
    with db() as c:
        rows = c.execute("""select a.*, p.hints_revealed, p.solution_viewed as peeked from attempts a
                            join progress p on p.user_id = a.user_id and p.slug = a.slug
                            where a.solved_at is not null and a.score is null""").fetchall()
        for a in rows:
            if a["slug"] not in meta:
                continue
            sc = scorer_for(a["slug"])(a["solved_at"] - a["started_at"], a["hints_revealed"], bool(a["peeked"]), a["checks"])
            c.execute("update attempts set score=?, score_detail=? where id=?", (sc["total"], json.dumps(sc), a["id"]))
            n += 1
        c.execute("""update progress set best_score = (select max(score) from attempts a
                       where a.user_id = progress.user_id and a.slug = progress.slug and a.solved_at is not null)
                     where first_solved_at is not null""")
    return n


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
            "select slug, started_at, ended_at, end_reason, checks, hints_used, solution_viewed, solved_at, score, score_detail from attempts where user_id=? order by started_at desc limit ?",
            (uid, limit))]


def leaderboard(slugs: list[str] | None = None, since: int | None = None, limit: int = 100) -> list[dict]:
    """Rank by points: per user, the best score per scenario (among solves since `since`), summed."""
    where, args = ["a.solved_at is not null"], []
    if slugs is not None:
        where.append(f"a.slug in ({','.join('?' * len(slugs))})")
        args += slugs
    if since:
        where.append("a.solved_at >= ?")
        args.append(since)
    with db() as c:
        rows = c.execute(f"""
            with best as (
              select a.user_id, a.slug, max(a.score) as score, min(a.solved_at - a.started_at) as secs,
                     max(a.solved_at) as last_at
              from attempts a where {' and '.join(where)} group by a.user_id, a.slug)
            select u.id, u.name, u.picture,
                   sum(b.score) as points, count(*) as solved,
                   sum(case when b.score > 0 then 1 else 0 end) as solved_clean,
                   sum(b.secs) as total_seconds, max(b.last_at) as last_solved_at
            from best b join users u on u.id = b.user_id
            group by u.id
            order by points desc, solved desc, total_seconds asc
            limit ?""", (*args, limit)).fetchall()
    out, rank, prev = [], 0, None
    for i, r in enumerate(rows):
        key = (r["points"], r["solved"], r["total_seconds"])
        rank = rank if key == prev else i + 1
        prev = key
        out.append(dict(r) | {"rank": rank})
    return out


def user_points(uid: int) -> int:
    with db() as c:
        return c.execute("select coalesce(sum(best_score), 0) from progress where user_id=?", (uid,)).fetchone()[0]
