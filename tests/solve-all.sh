#!/bin/bash
# For every scenario: the grader must FAIL on the broken box and PASS after the reference fix.
cd "$(dirname "$0")/.."
declare -A FIX
FIX[biggest-table]='echo archive.events > ~/solution'
FIX[wont-start]='sed -i "/128MBB/d" $PGDATA/postgresql.auto.conf; chmod 700 $PGDATA; pg_ctl -D $PGDATA -l /var/log/postgresql/postgresql.log -w start >/dev/null'
FIX[locked-out]='sed -i "/reject/d" $PGDATA/pg_hba.conf; psql -qX -c "select pg_reload_conf()" -c "alter role app login valid until '"'infinity'"'" >/dev/null; psql -qX -d billing -c "grant select on accounts to app"'
FIX[slow-query]='psql -qX -d shop -c "drop index orders_customer_id_idx" -c "create index on orders (customer_id, status, created_at desc)"'
FIX[blocked-checkout]='psql -qX -At -c "select pg_terminate_backend(pid) from pg_stat_activity where application_name='"'nightly_report'"'" -c "alter role reporting set idle_in_transaction_session_timeout='"'60s'"'" >/dev/null'
FIX[id-overflow]='psql -qX -d tracking -c "alter table events alter column id type bigint" -c "alter sequence events_id_seq as bigint" -c "alter table event_tags alter column event_id type bigint"'
FIX[too-many-connections]='psql -qX -At -c "select pg_terminate_backend(pid) from pg_stat_activity where usename='"'metrics'"'" -c "alter role metrics connection limit 5" >/dev/null'
rc=0
for s in "${!FIX[@]}"; do
  c=$(docker run -d --rm --init --network none --memory 512m --pids-limit 256 "saddb/$s:latest")
  until docker exec "$c" test -f /run/sad-ready 2>/dev/null; do sleep 0.5; done
  if docker exec "$c" /opt/sad/check.sh >/tmp/x 2>&1; then echo "✗ $s: check PASSED on the broken box"; rc=1; else echo "  $s broken: $(tail -1 /tmp/x)"; fi
  docker exec -u postgres "$c" bash -lc "${FIX[$s]}" >/dev/null 2>&1
  if out=$(docker exec "$c" /opt/sad/check.sh 2>&1); then echo "✓ $s fixed: $(echo "$out" | tail -1)"; else echo "✗ $s: still failing after fix: $out"; rc=1; fi
  docker rm -f "$c" >/dev/null
done
exit $rc
