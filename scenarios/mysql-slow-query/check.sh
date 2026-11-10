#!/bin/bash
. /usr/local/lib/sad/lib.sh
q "select 1" | grep -q 1 || fail "MySQL is not running"
n=$(q "select count(*) from orders" shop)
[ "$n" = "400000" ] || fail "orders should still have 400000 rows (has '$n')"
for c in 4242 17 9001; do
  ex=$(q "explain format=tree SELECT * FROM orders WHERE customer_ref = $c ORDER BY created_at DESC LIMIT 20" shop)
  echo "$ex" | grep -qi 'table scan' && fail "customer $c: still a full table scan"
  echo "$ex" | grep -qiE 'index lookup|index range scan|index scan' || fail "customer $c: no index used"
  rows=$(q "explain format=json SELECT * FROM orders WHERE customer_ref = $c ORDER BY created_at DESC LIMIT 20" shop | grep -o '"rows_examined_per_scan": [0-9]*' | head -1 | grep -o '[0-9]*$')
  [ "${rows:-999999}" -lt 2000 ] || fail "customer $c: examines ~$rows rows"
  echo "customer $c: index used, ~$rows rows examined"
done
pass "the unchanged query uses an index"
