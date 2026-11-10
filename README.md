# sadDatabase

Broken databases, real shells. A SadServers-style trainer for DBA skills: pick a scenario, get a
terminal in the browser on a disposable box with a broken PostgreSQL, fix it, press **Check**.

## Run (lab box)
```
bin/sadb build                     # build base + all scenario images (~1-2 min)
uv run uvicorn app.main:app --host 127.0.0.1 --port 8090
```
Open http://127.0.0.1:8090/ (or tunnel it: `ssh -L 8090:127.0.0.1:8090 magickite`).

Env: `SADDB_SESSION_MINUTES` (default 45), `SADDB_MAX_SESSIONS` (default 4).

## How it works
- **One container per session** from `saddb/<slug>:latest`: `--network none`, 512 MB RAM, 1 CPU,
  256 pids, `no-new-privileges`. The player is the OS user `postgres` (no sudo). Expired sessions are
  reaped every 30 s.
- **Terminal**: xterm.js ⇄ WebSocket ⇄ `docker exec bash -l` (PTY) in `app/main.py`.
- **Grading**: `POST /api/sessions/{id}/check` runs `/opt/sad/check.sh` as root inside the box.
  `/opt/sad` is root-only, so players can't read graders.
- **Progress** is kept in the browser (localStorage). No accounts yet.

## Adding a scenario
`scenarios/<slug>/`:
| file | when it runs | purpose |
|---|---|---|
| `scenario.toml` | web app | title, difficulty, minutes, order, tags, summary, description (markdown), hints[], solution |
| `setup.sh` | `docker build`, as root | `pg_start`, load data, `pg_stop`, then break things. The data dir is baked into the image. |
| `start.sh` (optional) | container start, as root | runtime misbehaviour (blocking sessions, leaks). Default: `pg_start`. |
| `check.sh` | "Check" button, as root | exit 0 = solved. Print `PASS:`/`FAIL:` lines; the player sees them. |

Helpers from `/usr/local/lib/sad/lib.sh`: `pg_start`, `pg_stop`, `sql` (heredoc psql as superuser),
`q "select ..." [db]`, `pass`, `fail`.

Then `bin/sadb build <slug>`, add the reference fix to `tests/solve-all.sh`, and run it: every
scenario must **fail** on the fresh box and **pass** after the fix.
`bin/sadb shell <slug>` drops you into a throwaway box to play-test.

## Scenarios
| slug | difficulty | skill |
|---|---|---|
| biggest-table | easy | catalogs, TOAST, `pg_total_relation_size` |
| wont-start | easy | reading logs, `postgresql.auto.conf`, data dir perms |
| locked-out | medium | `pg_hba.conf`, role attributes, password expiry, grants |
| slow-query | medium | `EXPLAIN ANALYZE`, invalid indexes, composite indexes |
| blocked-checkout | medium | `pg_stat_activity`, `pg_blocking_pids`, idle-in-transaction timeout |
| id-overflow | medium | int4 sequence exhaustion, `ALTER COLUMN TYPE bigint`, FKs |
| too-many-connections | hard | reserved slots, terminating backends, role connection limits |
