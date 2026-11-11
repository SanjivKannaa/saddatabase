#!/bin/bash
. /usr/local/lib/sad/lib.sh
[ "$(nq 1 'select 1')" = 1 ] || fail "node1 is not running"
[ "$(nq 2 'select 1')" = 1 ] || fail "node2 is not running"
[ "$(rs 2 Replica_IO_Running)" = Yes ] || fail "node2's IO thread isn't running: $(rs 2 Last_IO_Error | cut -c1-200)"
[ "$(rs 2 Replica_SQL_Running)" = Yes ] || fail "node2's SQL thread isn't running: $(rs 2 Last_SQL_Error | cut -c1-200)"
[ "$(rs 2 Source_Port)" = 3306 ] || fail "node2 must replicate from node1"
g1=$(nq 1 "select @@gtid_executed" | tr -d '\n'); g2=$(nq 2 "select @@gtid_executed" | tr -d '\n')
[ "$(nq 2 "select gtid_subset('$g2', '$g1')")" = 1 ] || fail "node2 has errant transactions node1 never had: $(nq 2 "select gtid_subtract('$g2', '$g1')")"
[ "$(nq 2 "select wait_for_executed_gtid_set('$g1', 15)")" = 0 ] || fail "node2 hasn't caught up with node1"
for t in orders customers; do
  [ "$(nq 1 "checksum table bookstore.$t" | awk '{print $2}')" = "$(nq 2 "checksum table bookstore.$t" | awk '{print $2}')" ] || fail "bookstore.$t is different on node2: replication runs, but the data has drifted"
done
[ "$(nq 2 'select @@super_read_only')" = 1 ] || fail "node2 isn't super_read_only: the next hand-made 'fix' will break it again"
grep -qsE '^\s*super[_-]read[_-]only\s*=\s*(1|ON|on)' /etc/mysql/nodes/node2.cnf || grep -qs '"super_read_only"' /srv/mysql/node2/mysqld-auto.cnf || fail "super_read_only isn't persistent on node2"
pass "replication is healthy, node2 matches node1 table for table, no errant GTIDs, and node2 is locked down"
