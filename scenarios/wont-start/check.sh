#!/bin/bash
. /usr/local/lib/sad/lib.sh
q "select 1" | grep -q 1 || fail "PostgreSQL is not accepting connections"
n=$(q "select count(*) from items" inventory)
[ "$n" = "5000" ] || fail "database inventory is missing data (items has '${n:-nothing}' rows, expected 5000)"
pass "PostgreSQL is up and inventory.items still has 5000 rows"
