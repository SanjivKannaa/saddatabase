#!/bin/bash
. /usr/local/lib/sad/lib.sh
[ "$(nq 1 'select 1')" = 1 ] || fail "node1 (port 5432) isn't running"
px=$(nq 1 "select string_agg(gid, ', ') from pg_prepared_xacts")
[ -z "$px" ] || fail "a prepared transaction is still open ($px): it holds the horizon, even across restarts"
idle=$(nq 1 "select string_agg(usename || ' (pid ' || pid || ', ' || date_trunc('second', now() - xact_start) || ')', ', ') from pg_stat_activity where state like 'idle in transaction%' and xact_start < now() - interval '60 seconds'")
[ -z "$idle" ] || fail "session(s) idle in transaction for over a minute: $idle"
old=$(nq 1 "select usename || ' (' || coalesce(state, '?') || ', xmin age ' || age(backend_xmin) || ')' from pg_stat_activity where backend_xmin is not null and xact_start < now() - interval '60 seconds' and pid <> pg_backend_pid() order by age(backend_xmin) desc limit 1")
[ -z "$old" ] || fail "a session has held its snapshot for over a minute: $old"
mpt=$(nq 1 "show max_prepared_transactions")
[ "$mpt" = 0 ] || fail "max_prepared_transactions is $mpt: disable two-phase commit (0, needs a restart)"
nq 1 "VACUUM tracking_events" parcels >/dev/null
read -r live dead <<<"$(nq 1 "select n_live_tup, n_dead_tup from pg_stat_user_tables where relname = 'tracking_events'" parcels | tr '|' ' ')"
[ "${dead:-999999}" -lt 5000 ] || fail "after VACUUM, tracking_events still has $dead dead rows it couldn't remove: something still holds the xmin horizon"
t=$(PGPASSWORD=Report-Parcel-2026 psql -X -At -h 127.0.0.1 -p 5432 -U reporting -d parcels -c "select setting from pg_settings where name = 'idle_in_transaction_session_timeout'" 2>&1)
[[ "$t" =~ ^[0-9]+$ ]] || fail "reporting can't log in any more: $(echo "$t" | head -1)"
[ "$t" -gt 0 ] || fail "a reporting session can still sit idle in transaction forever (idle_in_transaction_session_timeout is 0 for it)"
[ "$t" -le 3600000 ] || fail "reporting's idle_in_transaction_session_timeout is $((t / 60000)) min: at most an hour"
out=$(PGPASSWORD=Report-Parcel-2026 psql -X -At -h 127.0.0.1 -p 5432 -U reporting -d parcels -c "select count(*) > 0 from shipments" 2>&1)
[ "$out" = t ] || fail "reporting can't read shipments any more: $(echo "$out" | head -1)"
pass "VACUUM leaves $dead dead rows in tracking_events; no prepared transactions (and none allowed); reporting sessions time out after $((t / 1000)) s idle in transaction"
