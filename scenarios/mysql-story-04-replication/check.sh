#!/bin/bash
. /usr/local/lib/sad/lib.sh
[ "$(nq 1 'select 1')" = 1 ] || fail "node1 is not running"
[ "$(nq 2 'select 1')" = 1 ] || fail "node2 is not running"
[ "$(nq 1 'select @@server_id')" != "$(nq 2 'select @@server_id')" ] || fail "node1 and node2 have the same server_id"
[ "$(nq 2 'select @@gtid_mode')" = ON ] || fail "node2 doesn't have gtid_mode=ON"
[ "$(rs 2 Replica_IO_Running)" = Yes ] || fail "node2's IO thread isn't running: $(rs 2 Last_IO_Error | cut -c1-200)"
[ "$(rs 2 Replica_SQL_Running)" = Yes ] || fail "node2's SQL thread isn't running: $(rs 2 Last_SQL_Error | cut -c1-200)"
[ "$(rs 2 Source_Port)" = 3306 ] || fail "node2 replicates from port $(rs 2 Source_Port), not node1 (3306)"
[ "$(rs 2 Auto_Position)" = 1 ] || fail "node2 isn't using GTID auto-positioning (SOURCE_AUTO_POSITION=1)"
u=$(rs 2 Source_User); [[ "$u" != root && "$u" != sadgrader && -n "$u" ]] || fail "node2 replicates as '$u': use a dedicated replication user"
[ "$(nq 2 'select @@super_read_only')" = 1 ] || fail "node2 isn't super_read_only: anyone (even root) could write to it"
grep -qsE '^\s*super[_-]read[_-]only\s*=\s*(1|ON|on)' /etc/mysql/nodes/node2.cnf || grep -qs '"super_read_only"' /srv/mysql/node2/mysqld-auto.cnf || fail "super_read_only isn't persistent: node2 would come back writable after a restart"
probe="probe-$(date +%s%N)"
nq 1 "insert into bookstore.customers (name, email) values ('$probe', 'grader@lumen.test')" >/dev/null
for i in $(seq 20); do [ "$(nq 2 "select count(*) from bookstore.customers where name='$probe'")" = 1 ] && break; sleep 0.5; done
[ "$(nq 2 "select count(*) from bookstore.customers where name='$probe'")" = 1 ] || fail "a row written on node1 didn't show up on node2 within 10 s"
gtids=$(nq 1 "select @@gtid_executed" | tr -d '\n')
[ "$(nq 2 "select wait_for_executed_gtid_set('$gtids', 15)")" = 0 ] || fail "node2 didn't catch up with node1"
# the writer keeps bumping loyalty_points, so compare the columns it never touches
CS="select count(*), bit_xor(crc32(concat_ws('#', id, name, email))) from bookstore.customers"
a=$(nq 1 "$CS"); b=$(nq 2 "$CS")
[ "$a" = "$b" ] || fail "bookstore.customers differs between node1 and node2: the seed wasn't consistent"
mx=$(nq 1 "select max(id) - 10 from bookstore.orders")
[ "$(nq 2 "select count(*) from bookstore.orders where id <= $mx")" = "$(nq 1 "select count(*) from bookstore.orders where id <= $mx")" ] || fail "node2 is missing orders that node1 has: the seed lost transactions"
pass "node2 is a GTID replica of node1 (user $u), read-only even for root, persistently, and in sync"
