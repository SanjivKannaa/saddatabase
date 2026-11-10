#!/bin/bash
. /usr/local/lib/sad/lib.sh
q "select 1" | grep -q 1 || fail "PostgreSQL is not running"
out=$(su postgres -c "PGPASSWORD=w3b psql -X -At -h 127.0.0.1 -U web app -c 'select 42'" 2>&1)
[ "$out" = "42" ] || fail "web still can't connect: $(echo "$out" | head -1)"
lim=$(q "select rolconnlimit from pg_roles where rolname='metrics'")
[ "$lim" -ge 0 ] && [ "$lim" -le 5 ] 2>/dev/null || fail "role metrics can still open unlimited/too many connections (limit = $lim)"
pass "web connects, and metrics is limited to $lim connections"
