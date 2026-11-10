#!/bin/bash
. /usr/local/lib/sad/lib.sh
q "select 1" | grep -q 1 || fail "PostgreSQL is not running"
n=$(q "select count(*) from events" tracking)
[ "$n" -ge 100000 ] 2>/dev/null || fail "existing events were lost (count = '$n')"
out=$(q "with e as (insert into events (kind, payload) values ('click','{}') returning id), t as (insert into event_tags select id, 'graded' from e returning event_id) select event_id from t" tracking)
[[ "$out" =~ ^[0-9]+$ ]] || fail "inserting an event + tag still fails: $(su postgres -c "psql -X -At -d tracking -c \"insert into events (kind) values ('x')\"" 2>&1 | head -1)"
[ "$out" -gt 2147483647 ] || fail "the new id ($out) re-uses the old id range; restarting the sequence only delays the problem"
for col in "events.id" "event_tags.event_id"; do
  ty=$(q "select format_type(atttypid, atttypmod) from pg_attribute where attrelid='${col%.*}'::regclass and attname='${col#*.}'" tracking)
  [ "$ty" = "bigint" ] || fail "$col is still $ty"
done
pass "events get id $out and can be tagged; ids are bigint end to end"
