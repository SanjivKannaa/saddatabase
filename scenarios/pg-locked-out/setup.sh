#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
pg_start
sql <<'SQL'
create role app password 'Tr0ub4dor-and-3' nologin valid until '2024-03-31';
create database billing;
\c billing
create table accounts (id serial primary key, name text, balance numeric(12,2));
insert into accounts (name, balance) select 'acct '||g, random()*1000 from generate_series(1,1234) g;
revoke all on accounts from public;
SQL
pg_stop
hba=$PGDATA/pg_hba.conf
sed -i '/^host/d' $hba
cat >> $hba <<'HBA'
# --- SEC-2291 hardening: block legacy app access ---
host    billing         app             127.0.0.1/32            reject
# --- standard access ---
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256
HBA
mkdir -p /srv/app
echo 'DATABASE_URL=postgresql://app:Tr0ub4dor-and-3@127.0.0.1:5432/billing' > /srv/app/app.env
chmod 644 /srv/app/app.env
