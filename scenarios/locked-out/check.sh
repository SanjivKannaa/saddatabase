#!/bin/bash
. /usr/local/lib/sad/lib.sh
grep -q '^DATABASE_URL=postgresql://app:Tr0ub4dor-and-3@127.0.0.1:5432/billing$' /srv/app/app.env || fail "/srv/app/app.env was changed"
q "select 1" | grep -q 1 || fail "PostgreSQL is not running"
t=$(q "select count(*) from pg_hba_file_rules where type like 'host%' and auth_method='trust'")
[ "$t" = "0" ] || fail "trust authentication is not allowed for host connections"
out=$(su postgres -c "psql -X -At 'postgresql://app:Tr0ub4dor-and-3@127.0.0.1:5432/billing' -c 'select count(*) from accounts'" 2>&1)
[ "$out" = "1234" ] || fail "the app still can't read accounts: $(echo "$out" | head -1)"
pass "the app connects and reads 1234 accounts"
