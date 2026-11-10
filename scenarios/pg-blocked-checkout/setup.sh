#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
pg_start
sql <<'SQL'
create role reporting login password 'r3port';
create role shop login password 'sh0p';
create database store;
\c store
create table inventory (sku text primary key, qty int not null, updated_at timestamptz default now());
insert into inventory (sku, qty) select 'A-'||g, 100 from generate_series(100,999) g;
grant select, update on inventory to reporting, shop;
SQL
pg_stop
