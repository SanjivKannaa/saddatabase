#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
pg_start
sql <<'SQL'
create database inventory;
\c inventory
create table items (id serial primary key, sku text unique, qty int);
insert into items (sku, qty) select 'SKU-'||g, (random()*100)::int from generate_series(1,5000) g;
SQL
pg_stop
echo "shared_buffers = '128MBB'" >> $PGDATA/postgresql.auto.conf
sed -i 's/^#\?shared_buffers.*/shared_buffers = 128MB			# tuned by dave/' $PGDATA/postgresql.conf
chmod 755 $PGDATA
