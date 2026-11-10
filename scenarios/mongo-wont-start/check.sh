#!/bin/bash
. /usr/local/lib/sad/lib.sh
[ "$(q 'db.runCommand({ping:1}).ok')" = "1" ] || fail "mongod is not running"
n=$(q 'db.items.countDocuments()' inventory)
[ "$n" = "5000" ] || fail "inventory.items has '${n:-nothing}' documents, expected 5000"
pass "mongod is up and inventory.items has 5000 documents"
