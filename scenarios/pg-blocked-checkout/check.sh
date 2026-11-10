#!/bin/bash
. /usr/local/lib/sad/lib.sh
q "select 1" | grep -q 1 || fail "PostgreSQL is not running"
out=$(PGPASSWORD=sh0p su postgres -c "PGPASSWORD=sh0p psql -X -At -h 127.0.0.1 -U shop store -c \"set lock_timeout='3s'; update inventory set qty = qty where sku = 'A-100' returning sku\"" 2>&1)
echo "$out" | grep -q 'A-100' || fail "updates to A-100 still block: $(echo "$out" | tail -1)"
t=$(su postgres -c "PGPASSWORD=r3port psql -X -At -h 127.0.0.1 -U reporting store -c \"select setting::int from pg_settings where name='idle_in_transaction_session_timeout'\"" 2>&1)
[[ "$t" =~ ^[0-9]+$ ]] || fail "could not check settings for role reporting: $t"
[ "$t" -gt 0 ] && [ "$t" -le 60000 ] || fail "a reporting session can still idle in a transaction for too long (idle_in_transaction_session_timeout = ${t}ms)"
pass "A-100 updates go through, and reporting sessions idle in a transaction get cut off after ${t}ms"
