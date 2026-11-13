#!/bin/bash
. /usr/local/lib/sad/lib.sh
[ "$(nq 1 'select 1')" = 1 ] || fail "nothing answers on port 5432"
v=$(nq 1 'select current_setting($$server_version_num$$)::int / 10000')
[ "$v" = 17 ] || fail "the server on port 5432 is PostgreSQL $v, not 17"
pgrep -f '/usr/lib/postgresql/16/bin/postgres' >/dev/null && fail "a PostgreSQL 16 server is still running: the old cluster should stay stopped"
dir=$(nq 1 'show data_directory'); name=$(basename "$dir")
[[ "$dir" == /srv/pg/node* ]] || fail "the new cluster lives in $dir: put it in /srv/pg/nodeN so dbctl can manage it"
runuser -u postgres -- dbctl restart "$name" >/dev/null || fail "$name doesn't come back after a restart: see /var/log/postgresql/$name.log"
[ "$(nq 1 'select current_setting($$server_version_num$$)::int / 10000')" = 17 ] || fail "after a restart, port 5432 isn't PostgreSQL 17 any more"
[ "$(nq 1 "select count(*) from pg_database where datname = 'parcels'")" = 1 ] || fail "there's no parcels database on the new server"
[ "$(tsum 1 shipments)" = "$(cat /opt/sad/shipments.sum)" ] || fail "parcels.shipments isn't what it was on 16"
[ "$(tsum 1 customers)" = "$(cat /opt/sad/customers.sum)" ] || fail "parcels.customers isn't what it was on 16"
[ "$(nq 1 "select count(*) from pg_indexes where indexname = 'customers_name_trgm'" parcels)" = 1 ] || fail "the pg_trgm index customers_name_trgm is gone"
[ "$(nq 1 "select count(*) from customers where name % 'Customr 42'" parcels)" -ge 1 ] 2>/dev/null || fail "trigram search (pg_trgm) doesn't work on the new server"
out=$(runuser -u postgres -- psql -X -At -p 5432 -d parcels -c "select count(*) >= 0 from pg_stat_statements" 2>&1)
[ "$out" = t ] || fail "pg_stat_statements doesn't work on the new server: $(echo "$out" | head -1)"
[ "$(nq 1 "select count(*) from pg_stats where schemaname = 'public' and tablename = 'shipments'" parcels)" -gt 0 ] || fail "the planner has no statistics for shipments: pg_upgrade doesn't carry them over (analyze)"
bad=$(nq 1 "select string_agg(line_number || ': ' || type || ' ' || auth_method, ', ') from pg_hba_file_rules where auth_method in ('trust','password')")
[ -z "$bad" ] || fail "the new pg_hba.conf has trust/password lines (line $bad)"
out=$(PGPASSWORD=Parcel-App-2026 psql -X -h 127.0.0.1 -p 5432 -U parcels_app -d parcels -Atc "select count(*) from shipments" 2>&1) \
  || fail "parcels_app can't log in over TCP with its password: $(echo "$out" | head -1)"
pass "PostgreSQL 17 on 5432 with all of parcels, pg_trgm, pg_stat_statements and fresh statistics; 16 is stopped"
