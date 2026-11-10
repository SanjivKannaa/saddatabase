#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
pg_start
sql <<'SQL'
create database shop;
\c shop
create table customers (id serial primary key, name text, email text);
insert into customers (name, email) select 'customer '||g, 'c'||g||'@example.com' from generate_series(1,60000) g;
create table orders (id bigserial primary key, customer_id int, total numeric(10,2), created_at timestamptz default now());
insert into orders (customer_id, total, created_at) select (random()*59999+1)::int, random()*500, now() - random()*interval '365 days' from generate_series(1,250000);
create index on orders (customer_id); create index on orders (created_at);
create table audit_log (id bigserial primary key, at timestamptz default now(), action text, detail text);
insert into audit_log (action, detail) select 'update', repeat('row changed ', 12) || g from generate_series(1,220000) g;
create schema archive;
create table archive.events (id serial primary key, kind text, body text);
alter table archive.events alter column body set storage external;
insert into archive.events (kind, body)
  select 'export', (select string_agg(md5(random()::text || g || i), '') from generate_series(1,120) i)
  from generate_series(1,20000) g;
vacuum analyze;
SQL
pg_stop
