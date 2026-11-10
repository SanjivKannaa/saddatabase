#!/bin/bash
. /usr/local/lib/sad/lib.sh
[ "$(q 'db.runCommand({ping:1}).ok')" = "1" ] || fail "mongod is not running"
n=$(q 'db.orders.estimatedDocumentCount()' shop)
[ "$n" = "300000" ] || fail "orders should still have 300000 documents (has '$n')"
for c in 4242 17 9001; do
  r=$(q "const e = db.orders.find({customerId: $c, status: 'pending'}).sort({createdAt: -1}).limit(20).explain('executionStats');
         const s = JSON.stringify(e.queryPlanner.winningPlan);
         [e.executionStats.totalDocsExamined, s.includes('COLLSCAN'), s.includes('\"SORT\"')].join(' ')" shop)
  read ex coll sort <<< "$r"
  [ "$coll" = "false" ] || fail "customer $c: still a collection scan"
  [ "$sort" = "false" ] || fail "customer $c: still sorts in memory"
  [ "${ex:-99999}" -le 50 ] || fail "customer $c: examined $ex documents (max 50)"
  echo "customer $c: $ex documents examined"
done
pass "the query uses an index for filter and sort"
