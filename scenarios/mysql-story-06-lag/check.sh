#!/bin/bash
. /usr/local/lib/sad/lib.sh
[ "$(nq 1 'select 1')" = 1 ] || fail "node1 is not running"
[ "$(nq 2 'select 1')" = 1 ] || fail "node2 is not running"
age1=$(nq 1 "select timestampdiff(second, ts, now(6)) from bookstore.heartbeat")
[ "${age1:-99}" -le 3 ] || fail "node1's heartbeat isn't updating: the shop's traffic must keep running"
[ "$(rs 2 Replica_IO_Running)" = Yes ] && [ "$(rs 2 Replica_SQL_Running)" = Yes ] || fail "replication on node2 isn't running (both threads must be Yes)"
for i in $(seq 1 6); do
  lag=$(nq 2 "select timestampdiff(second, ts, now(6)) from bookstore.heartbeat")
  [ "${lag:-999}" -lt 5 ] || fail "node2 is ${lag}s behind node1 (heartbeat)"
  sleep 1
done
echo "lag stayed under 5 s for 6 s (last: ${lag}s)"
[ "$(nq 2 "select count(*) from information_schema.processlist where id <> connection_id() and (state like '%global read lock%' or (user = 'backup_agent' and command <> 'Sleep'))")" = 0 ] || fail "something on node2 still holds or waits for a global read lock"
s=/srv/backup/nightly.sh
grep -vE '^\s*#' $s | grep -qE -- '--lock-all-tables|-x( |$)|FLUSH TABLES WITH READ LOCK' && fail "nightly.sh still takes a global read lock: tonight's backup will freeze replication again"
grep -vE '^\s*#' $s | grep -q -- '--single-transaction' || fail "nightly.sh should take a consistent InnoDB snapshot with --single-transaction"
grep -vE '^\s*#' $s | grep -q mysqldump || fail "nightly.sh no longer takes a backup at all"
pass "node2 is caught up and stays caught up, and the nightly backup won't block replication again"
