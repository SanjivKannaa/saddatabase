# sadDatabase

Broken databases, real shells. A SadServers-style trainer for DBA skills: pick a track, get a
terminal in the browser on a disposable box with a broken database, fix it, press **Check**.

**Tracks:** PostgreSQL 17 (7 scenarios), MySQL 8.4 (4), MongoDB 7.0 (4), Redis 8 (3).
Sign in with Google; progress, attempts, checks, hints and solution peeks are stored per user, with a
profile page and a leaderboard (clean solves first).

## Story mode: *Lumen Books* (MySQL)
You're the first DBA at an online bookstore. Nine chapters, each a real box with up to three `mysqld` nodes:

| Act | Chapter | You do |
|---|---|---|
| I · Day one | 1 The empty server | install 8.4 from the official tarball: my.cnf, initialise, secure root, app user |
| | 2 Ship it in a container | review/fix a compose file: pinned image, named volume, secret file, 127.0.0.1 port, healthcheck |
| II · Don't lose the data | 3 The table that wasn't there | point-in-time recovery: dump + binlog replay to just before a `DROP TABLE` |
| III · A second copy | 4 A second copy | build GTID replication under live writes (server_id, GTID, public-key auth, super_read_only) |
| | 5 Replication broke at 3 a.m. | duplicate-key stop, hidden drift, errant GTIDs |
| | 6 The replica is 20 minutes behind | a hung backup holding a global read lock; fix the backup script |
| IV · When the primary dies | 7 The primary is dead | manual failover: promote the replica with every GTID, re-home the other, move the app |
| | 8 Let the robot do it | configure orchestrator (Percona 3.2.6-24); the grader kills the primary and it must recover |
| V · Change without downtime | 9 ALTER TABLE without the freeze | gh-ost 1.1.11 under live traffic; blocking ALTERs are detected |

The story lives in `stories/mysql/story.toml` (intro, cast, acts → chapter slugs); chapters are ordinary scenarios
(`scenarios/mysql-story-*`) with `base = "mysql-lab"`, a `narrative` and an optional `box_minutes`.
`images/mysql-lab-base` runs nodes `node1..3` (ports 3306–3308) with `dbctl start|stop|status nodeN`, `node1/2/3`
clients, `orcctl` for orchestrator, and the tools from `bin/fetch-vendor` (MySQL tarball, gh-ost, orchestrator;
checksums pinned in `images/mysql-lab-base/vendor.sha256`, downloads gitignored).

## Play in your terminal (no login)
```
uv tool install "git+https://github.com/SanjivKannaa/saddatabase#subdirectory=cli"
saddb story                                  # the Lumen Books story, chapter by chapter
saddb list && saddb start pg-wont-start      # then: saddb check / hint / extend / end / progress
```
Only needs Docker. Same scenarios and scoring as the website, progress kept locally. See [cli/README.md](cli/README.md).
Images come from local `saddb/<slug>` builds or `ghcr.io/sanjivkannaa/saddb-<slug>` (publish with `bin/sadb publish`).

## Run
```
bin/sadb build                     # engine bases + all scenario images (~5 min the first time)
cp .env.example .env && chmod 600 .env   # then fill it in
uv run uvicorn app.main:app --host 127.0.0.1 --port 8090 --proxy-headers --forwarded-allow-ips 127.0.0.1
```
On magickite it's published as https://sad.db.magickite by `sudo deploy/install-magickite.sh`
(nginx vhost, cert SAN, Google callback route, systemd user unit).

### Settings (`.env`, environment wins)
| var | meaning |
|---|---|
| `SADDB_PUBLIC_URL` | where users reach the site, e.g. `https://sad.db.magickite` |
| `SADDB_OAUTH_REDIRECT_URL` | Google callback. Google only accepts public suffixes or `localhost`, so on the lab box it is `https://magickite.tail835779.ts.net/sad-auth/callback`, proxied to `/auth/callback` |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | OAuth web client; the redirect URL above must be registered on it |
| `SADDB_SECRET_KEY` | signs session cookies and login tickets; never change it casually (logs everyone out) |
| `SADDB_ALLOWED_EMAILS` | optional comma list of emails and/or `@domain`s; empty = any verified Google account |
| `SADDB_DEV_LOGIN` | `1` enables `/auth/dev?email=` for direct loopback requests only. Testing only |
| `SADDB_BOX_MINUTES`, `SADDB_EXTEND_MINUTES`, `SADDB_MAX_EXTENSIONS` | box lifetime 15 min, extendable +15 min up to 2 times (45 max) |
| `SADDB_MAX_SESSIONS` | global box cap (4); one box per user, enforced atomically |
| `SADDB_DB` | SQLite path (default `data/saddb.sqlite`) |

## How it works
- **One container per play session** from `saddb/<slug>:latest`: `--network none`, memory from the image's
  `saddb.mem` label, 1 CPU, 256 pids, `no-new-privileges`. Labelled with its owner, and every API and
  terminal call checks ownership. The reaper removes expired boxes and closes their attempts.
- **The player** is the database's service account (`postgres`, `mysql`, `mongodb`, `redis`; image label
  `saddb.user`), without sudo, with `dbctl start|stop|restart|status`. `/opt/sad` (graders, setup) is root-only.
- **Terminal**: xterm.js ⇄ WebSocket (same-origin check + session cookie) ⇄ `docker exec bash -l`.
- **Grading**: `/opt/sad/check.sh` runs as root in the box; exit 0 = solved. MySQL's grader logs in with its own
  `auth_socket` account, so it works even if the player changes the root password.
- **Login**: Google authorization-code flow → userinfo (verified email) → signed single-use ticket →
  `PUBLIC_URL/auth/ticket` sets the session. A nonce cookie set at `/auth/login` must match (no login CSRF).
- **Data** (SQLite): `users`, `progress` (per user × scenario: hints revealed, solution viewed, first solve, best
  time), `attempts` (one per box: start/end, checks, hints, solved_at). Hints and solutions are served one at a
  time by the API, so reveals are recorded.

## Adding a scenario
`scenarios/<slug>/` (slug prefix = engine: `pg-`, `mysql-`, `mongo-`, `redis-`):
| file | when it runs | purpose |
|---|---|---|
| `scenario.toml` | web app | `engine` (+ optional `base`, `narrative`, `box_minutes`), title, difficulty, minutes, `order` (position in the track), tags, summary, description (markdown), hints[], solution |
| `setup.sh` | `docker build`, as root | `db_start`, load data, `db_stop`, then break things. Data is baked into the image. |
| `start.sh` (optional) | box start, as root | runtime misbehaviour (blocking sessions, leaks). Default: `db_start`. |
| `check.sh` | "Check" button, as root | exit 0 = solved. Print `PASS:`/`FAIL:` lines; the player sees them. |

Helpers from `/usr/local/lib/sad/lib.sh` on every engine: `db_start`, `db_stop`, `pass`, `fail`, plus
`sql`/`q` (Postgres, MySQL), `js`/`q` (MongoDB), `r` (redis-cli).

Run `bin/sadb catalog` (the terminal client ships a copy of the catalogue; `bin/sadb catalog --check` fails if it is stale).
After changing the app, run `uv run python tests/smoke_api.py` (every endpoint, signed out and in).
Then add the reference fix as `tests/fixes/<slug>.sh` (runs as the player) and:
```
bin/sadb build <slug> && tests/solve-all.sh <slug>   # must FAIL on a fresh box and PASS after the fix
bin/sadb shell <slug>                                # play-test in a throwaway box
```

## Scenarios
| track | slug | level | skill |
|---|---|---|---|
| Postgres | pg-biggest-table | easy | catalogs, TOAST, `pg_total_relation_size` |
| | pg-wont-start | easy | reading logs, `postgresql.auto.conf`, data dir perms |
| | pg-locked-out | medium | `pg_hba.conf`, role attributes, password expiry, grants |
| | pg-slow-query | medium | `EXPLAIN ANALYZE`, invalid indexes, composite indexes |
| | pg-blocked-checkout | medium | `pg_stat_activity`, `pg_blocking_pids`, idle-in-transaction timeout |
| | pg-id-overflow | medium | int4 sequence exhaustion, `ALTER COLUMN TYPE bigint`, FKs |
| | pg-too-many-connections | hard | reserved slots, terminating backends, role connection limits |
| MySQL | mysql-wont-start | easy | removed 5.7 variables, error-log path |
| | mysql-locked-out | medium | locked account, expired password, inactive default role |
| | mysql-slow-query | medium | implicit type conversion disables an index |
| | mysql-metadata-lock | hard | metadata locks, idle open transactions, `KILL` |
| | mysql-emoji | easy | utf8mb3 → utf8mb4 without mangling old text |
| | mysql-too-many-connections | medium | reserved admin slot, KILL, MAX_USER_CONNECTIONS |
| | mysql-hot-query | medium | sys.statement_analysis / digests, index the costliest query |
| | mysql-binlog-disk | medium | PURGE BINARY LOGS safely around a paused replica, expiry policy |
| | mysql-lock-wait | medium | sys.innodb_lock_waits, forgotten transaction, wait_timeout |
| | mysql-replica-purged | hard | error 1236: reseed a replica (dump or CLONE) |
| MongoDB | mongo-wont-start | easy | YAML tabs, wrong `dbPath` |
| | mongo-slow-query | medium | `explain`, ESR compound index, in-memory sort |
| | mongo-auth | medium | `authSource`, user database, least-privilege roles |
| | mongo-duplicates | hard | aggregation dedupe, case-insensitive unique index |
| Redis | redis-aof-corrupt | easy | multi-part AOF, `redis-check-aof --fix` |
| | redis-oom | medium | `maxmemory-policy`, `CONFIG REWRITE` |
| | redis-bigkey | easy | `MEMORY USAGE`, `--memkeys` vs `--bigkeys` |
