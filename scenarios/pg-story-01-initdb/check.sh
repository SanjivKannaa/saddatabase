#!/bin/bash
. /usr/local/lib/sad/lib.sh
[ -f /srv/pg/node1/PG_VERSION ] || fail "there's no cluster in /srv/pg/node1"
[ "$(nq 1 'select 1')" = 1 ] || fail "nothing answers on port 5432 (local socket /var/run/postgresql): is node1 running? (sudo systemctl start postgresql@node1)"
[ "$(nq 1 'show data_directory')" = /srv/pg/node1 ] || fail "the server on 5432 runs from $(nq 1 'show data_directory'), not /srv/pg/node1"
runuser -u postgres -- /usr/local/lib/sad/svc restart node1 >/dev/null || fail "node1 doesn't come back after a restart: see /var/log/postgresql/node1.log"
[ "$(nq 1 'select current_setting($$server_version_num$$)::int / 10000')" = 17 ] || fail "node1 isn't PostgreSQL 17"
[ "$(nq 1 'show data_checksums')" = on ] || fail "data checksums are off (chosen at initdb, or with pg_checksums on a stopped cluster)"
la=$(nq 1 'show listen_addresses')
case ",${la// /}," in *'*'*|*,0.0.0.0,*|*,::,*) fail "listen_addresses = '$la' listens on every interface: localhost only" ;; esac
[ "$(nq 1 'show shared_buffers')" = 256MB ] || fail "shared_buffers is $(nq 1 'show shared_buffers'), not 256MB (after a restart)"
[ "$(nq 1 'select count(*) from pg_hba_file_rules where error is not null')" = 0 ] || fail "pg_hba.conf has lines the server can't parse: SELECT * FROM pg_hba_file_rules WHERE error IS NOT NULL"
bad=$(nq 1 "select string_agg(line_number || ': ' || type || ' ' || auth_method, ', ') from pg_hba_file_rules where auth_method in ('trust','password')")
[ -z "$bad" ] || fail "pg_hba.conf still has trust/password lines (line $bad)"
[ "$(nq 1 "select count(*) from pg_database where datname = 'parcels'")" = 1 ] || fail "there's no database parcels"
[ "$(nq 1 "select pg_encoding_to_char(encoding) from pg_database where datname = 'parcels'")" = UTF8 ] || fail "parcels isn't UTF8"
owner=$(nq 1 "select datdba::regrole from pg_database where datname = 'parcels'")
[ "$owner" = parcels_owner ] || fail "parcels is owned by $owner, not parcels_owner"
[ "$(nq 1 "select rolcanlogin from pg_roles where rolname = 'parcels_owner'")" = f ] || fail "parcels_owner can log in: it should be NOLOGIN (nobody logs in as the owner)"
read -r su cr db lg <<<"$(nq 1 "select rolsuper, rolcreaterole, rolcreatedb, rolcanlogin from pg_roles where rolname = 'parcels_app'" | tr '|' ' ')"
[ -n "$lg" ] || fail "there's no role parcels_app"
[ "$lg" = t ] || fail "parcels_app can't log in"
[ "$su$cr$db" = fff ] || fail "parcels_app has more than it needs (superuser/createrole/createdb): least privilege"
[[ "$(nq 1 "select rolpassword from pg_authid where rolname = 'parcels_app'")" == SCRAM-SHA-256* ]] || fail "parcels_app's password isn't stored as SCRAM"
out=$(PGPASSWORD=Parcel-App-2026 psql -X -h 127.0.0.1 -p 5432 -U parcels_app -d parcels -v ON_ERROR_STOP=1 -c "CREATE TABLE app.sad_probe (id int); DROP TABLE app.sad_probe;" 2>&1) \
  || fail "parcels_app can't connect over TCP and create a table in schema app: $(echo "$out" | head -2 | tr '\n' ' ')"
PGPASSWORD=wrong-password psql -X -h 127.0.0.1 -p 5432 -U parcels_app -d parcels -c "select 1" >/dev/null 2>&1 && fail "parcels_app got in with a WRONG password over TCP: that's trust in disguise"
pass "node1: PostgreSQL 17, checksums, localhost, no trust; parcels is owned by parcels_owner and parcels_app can work in schema app"
