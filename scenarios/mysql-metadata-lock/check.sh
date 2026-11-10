#!/bin/bash
. /usr/local/lib/sad/lib.sh
q "select 1" | grep -q 1 || fail "MySQL is not running"
up=$(q "show global status like 'Uptime'" | awk '{print $2}')
since=$(stat -c %Y /run/sad-ready); now=$(date +%s)
[ "$up" -ge $((now - since - 5)) ] || fail "mysqld was restarted; the task was to fix it live"
out=$(mysql -u sadgrader -N -B shop -e "set session lock_wait_timeout = 3; select name from products where id = 1" 2>&1)
[ "$out" = "product 1" ] || fail "reads on products still block: $out"
c=$(q "select count(*) from information_schema.columns where table_schema='shop' and table_name='products' and column_name='discount_pct'")
[ "$c" = "1" ] || fail "the migration didn't finish: products has no discount_pct column"
w=$(q "select count(*) from information_schema.processlist where state like 'Waiting for table metadata lock'")
[ "$w" = "0" ] || fail "$w threads are still waiting for a metadata lock"
pass "products is readable, discount_pct exists, nothing is waiting"
