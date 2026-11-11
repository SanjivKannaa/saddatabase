#!/bin/bash
. /usr/local/lib/sad/lib.sh
[ "$(nq 1 'select 1')" = 1 ] || fail "node1 is not running"
[ "$(nq 1 "select count(*) from information_schema.tables where table_schema='bookstore' and table_name='orders'")" = 1 ] || fail "bookstore.orders still doesn't exist"
n=$(nq 1 "select count(*) from bookstore.orders"); want_n=$(cat /opt/sad/orders.count)
[ "$n" = "$want_n" ] || fail "orders has $n rows; right before the DROP it had $want_n"
[ "$(nq 1 'checksum table bookstore.orders' | awk '{print $2}')" = "$(cat /opt/sad/orders.checksum)" ] || fail "orders has the right number of rows but not the right data (statuses or totals differ from right before the DROP)"
[ "$(nq 1 'checksum table bookstore.customers' | awk '{print $2}')" = "$(cat /opt/sad/customers.checksum)" ] || fail "bookstore.customers changed: today's customer updates were lost or altered"
pass "orders is back with all $n rows exactly as before the DROP, and customers kept today's changes"
