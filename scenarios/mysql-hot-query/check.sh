#!/bin/bash
. /usr/local/lib/sad/lib.sh
q "select 1" | grep -q 1 || fail "MySQL is not running"
[ "$(q "select count(*) from information_schema.statistics where table_schema='shop' and table_name='orders' and column_name='coupon_code' and seq_in_index=1")" -ge 1 ] || fail "the most expensive statement still scans orders: find it in sys.statement_analysis"
ex=$(q "explain format=tree SELECT id, total FROM orders WHERE coupon_code = 'BF2026-1234'" shop)
echo "$ex" | grep -qi 'table scan' && fail "the coupon lookup still does a table scan"
[ "$(q "select count(*) from orders" shop)" = 300000 ] || fail "orders lost rows"
pass "you found the costliest statement (the coupon lookup) and it now uses an index"
