#!/bin/bash
. /usr/local/lib/sad/lib.sh
# the grader's own sessions never wait for a synchronous standby (the write probe below does, on purpose)
export PGOPTIONS="-c synchronous_commit=local -c statement_timeout=20000"
port=$(sed -n 's/^DB_PORT=//p' /srv/app/db.env | tr -d ' "')
case $port in 5433) p=2 ;; 5434) p=3 ;; *) fail "the app still points at port ${port:-?}: set DB_PORT in /srv/app/db.env to the new primary" ;; esac
[ "$(nq $p 'select 1')" = 1 ] || fail "node$p (port $port, the app's primary) isn't running"
[ "$(nq $p 'select pg_is_in_recovery()')" = f ] || fail "node$p is still a standby: promote it (select pg_promote())"
# writes work (a primary waiting for a synchronous standby that doesn't exist hangs here)
probe="probe-$(date +%s%N)"
out=$(PGAPPNAME=sad-probe PGOPTIONS= timeout 6 runuser -u postgres -- psql -X -At -p $port -d parcels -c "insert into customers (name, email, city) values ('$probe', 'grader@parcel.test', 'Faro')" 2>&1)
if [ $? = 124 ]; then
  nq $p "select pg_cancel_backend(pid) from pg_stat_activity where application_name = 'sad-probe'" >/dev/null
  fail "a write on node$p hangs at COMMIT (6 s and counting): what is it waiting for? (SHOW synchronous_standby_names; pg_stat_activity wait events)"
fi
[[ "$out" == *"INSERT 0 1"* ]] || fail "a write on node$p failed: $(echo "$out" | head -1)"
# every delivery the app was told was saved
grep '^PD[0-9]*$' /opt/sad/committed | sort -u > /tmp/sad-committed
total=$(wc -l < /tmp/sad-committed)
runuser -u postgres -- psql -X -q -p $port -d parcels -c "create temp table c (tn text)" -c "\copy c from '/tmp/sad-committed'" \
  -At -c "select count(*) from c where tn not in (select tracking_no from shipments)" > /tmp/sad-missing 2>&1
missing=$(tail -1 /tmp/sad-missing)
[[ "$missing" =~ ^[0-9]+$ ]] || fail "couldn't compare deliveries on node$p: $(tail -1 /tmp/sad-missing)"
[ "$missing" = 0 ] || fail "node$p is missing $missing of the $total deliveries the app was told were saved: wrong standby promoted, or writes went to a primary that isn't this one"
gone=$(nq $p "select count(*) from shipments where tracking_no like 'PW%'" parcels)
[ "$gone" = 1500 ] || fail "node$p only has $gone of last week's 1500 PW shipments: it was a stale standby"
# the two others: standbys of the new primary, caught up
for o in 1 2 3; do
  [ $o = $p ] && continue
  [ "$(nq $o 'select 1')" = 1 ] || { [ $o = 1 ] && [ -f /etc/sad/node1.dead ] && fail "node1's host isn't back yet: wait for Inês's note in ~/ (it comes a little after the promotion)"; fail "node$o isn't running"; }
  [ "$(nq $o 'select pg_is_in_recovery()')" = t ] || fail "node$o isn't a standby: two primaries! (it must follow node$p)"
  IFS='|' read -r st sp <<<"$(nq $o 'select status, sender_port from pg_stat_wal_receiver')"
  [ "$st" = streaming ] || fail "node$o isn't streaming (WAL receiver: ${st:-none}): see /var/log/postgresql/node$o.log"
  [ "$sp" = "$port" ] || fail "node$o streams from port $sp, not from the new primary ($port)"
  for i in $(seq 20); do [ "$(nq $o "select count(*) from customers where name = '$probe'" parcels)" = 1 ] && break; sleep 0.5; done
  [ "$(nq $o "select count(*) from customers where name = '$probe'" parcels)" = 1 ] || fail "node$o didn't get a row written on node$p within 10 s"
done
recent=$(nq $p "select count(*) from shipments where created_at > now() - interval '5 seconds'" parcels)
[ "${recent:-0}" -ge 3 ] || fail "the app isn't saving deliveries on node$p (only ${recent:-0} in the last 5 s)"
pass "node$p is the primary with all $total acknowledged deliveries; the other two stream from it; the app is writing ($recent in 5 s)"
