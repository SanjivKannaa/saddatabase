#!/bin/bash
. /usr/local/lib/sad/lib.sh
f=/var/lib/postgresql/solution
[ -s "$f" ] || fail "no answer found in ~/solution"
ans=$(tr -d '[:space:]"' < "$f" | tr 'A-Z' 'a-z')
q "select 1" >/dev/null || fail "postgres is not running (you need it running to be graded)"
want=$(q "select n.nspname||'.'||c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='r' and n.nspname not in ('pg_catalog','information_schema') order by pg_total_relation_size(c.oid) desc limit 1" shop)
[ -n "$want" ] || fail "could not read database shop"
if [ "$ans" = "$want" ] || [ "$ans" = "${want#*.}" ]; then pass "$want is the biggest table"; else fail "'$ans' is not the biggest table"; fi
