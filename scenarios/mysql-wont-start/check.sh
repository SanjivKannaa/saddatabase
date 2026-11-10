#!/bin/bash
. /usr/local/lib/sad/lib.sh
q "select 1" | grep -q 1 || fail "MySQL is not running"
n=$(q "select count(*) from items" inventory)
[ "$n" = "5000" ] || fail "inventory.items has '${n:-nothing}' rows, expected 5000"
pass "MySQL is up and inventory.items has 5000 rows"
