#!/bin/bash
. /usr/local/lib/sad/lib.sh
[ "$(nq 1 'select 1')" = 1 ] || fail "node1 is not running"
[ "$(nq 2 'select 1')" = 1 ] || fail "node2 is not running"
[ "$(rs 2 Replica_IO_Running)" = Yes ] || fail "node2's IO thread isn't running: $(rs 2 Last_IO_Error | cut -c1-180)"
[ "$(rs 2 Replica_SQL_Running)" = Yes ] || fail "node2's SQL thread isn't running: $(rs 2 Last_SQL_Error | cut -c1-180)"
[ "$(rs 2 Source_Port)" = 3306 ] && [ "$(rs 2 Auto_Position)" = 1 ] || fail "node2 must replicate from node1 with GTID auto-positioning"
g1=$(nq 1 "select @@gtid_executed" | tr -d '\n'); g2=$(nq 2 "select @@gtid_executed" | tr -d '\n')
[ "$(nq 2 "select gtid_subset('$g2', '$g1')")" = 1 ] || fail "node2 has transactions node1 never had: $(nq 2 "select gtid_subtract('$g2', '$g1')")"
[ "$(nq 2 "select wait_for_executed_gtid_set('$g1', 30)")" = 0 ] || fail "node2 hasn't caught up"
[ "$(nq 1 'checksum table bookstore.customers' | awk '{print $2}')" = "$(nq 2 'checksum table bookstore.customers' | awk '{print $2}')" ] || fail "bookstore.customers differs between node1 and node2"
mx=$(nq 1 "select max(id) - 5 from bookstore.orders")
[ "$(nq 1 "select count(*), sum(total) from bookstore.orders where id <= $mx")" = "$(nq 2 "select count(*), sum(total) from bookstore.orders where id <= $mx")" ] || fail "bookstore.orders differs between node1 and node2"
[ "$(nq 2 'select @@super_read_only')" = 1 ] || fail "node2 isn't super_read_only"
grep -qsE '"super_read_only"[^}]*"Value": *"ON"' /srv/mysql/node2/mysqld-auto.cnf || grep -qsE '^\s*super[_-]read[_-]only\s*=\s*(1|ON|on)' /etc/mysql/nodes/node2.cnf || fail "super_read_only isn't persistent on node2"
pass "node2 is reseeded, identical to node1, replicating and caught up, and read-only for good"
