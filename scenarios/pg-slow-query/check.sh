#!/bin/bash
. /usr/local/lib/sad/lib.sh
q "select 1" | grep -q 1 || fail "PostgreSQL is not running"
n=$(q "select count(*) from orders" shop)
[ "$n" = "1200000" ] || fail "orders should still have 1200000 rows (has '${n}')"
for c in 4242 17 9001; do
  plan=$(q "explain (analyze, format json) select * from orders where customer_id = $c and status = 'pending' order by created_at desc limit 20" shop)
  echo "$plan" | grep -q '"Node Type": "Seq Scan"' && fail "customer $c: the query still does a sequential scan on orders"
  ms=$(echo "$plan" | grep -o '"Execution Time": [0-9.]*' | grep -o '[0-9.]*$')
  awk -v t="$ms" 'BEGIN{exit !(t < 5)}' || fail "customer $c: execution took ${ms} ms (need < 5 ms)"
  echo "customer $c: ${ms} ms"
done
pass "the query uses an index and runs in under 5 ms"
