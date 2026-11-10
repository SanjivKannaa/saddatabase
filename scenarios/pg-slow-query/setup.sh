#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
pg_start
sql <<'SQL'
create database shop;
\c shop
create table orders (
  id bigserial primary key,
  customer_id int not null,
  status text not null,
  total numeric(10,2),
  created_at timestamptz not null,
  note text
);
insert into orders (customer_id, status, total, created_at, note)
select (random()*9999+1)::int,
       (array['pending','paid','shipped','delivered'])[1 + (random()*3)::int],
       random()*300,
       now() - random()*interval '730 days',
       'order note ' || g
from generate_series(1, 1200000) g;
create index orders_status_idx on orders (status);
create index orders_customer_id_idx on orders (customer_id);
update pg_index set indisvalid = false where indexrelid = 'orders_customer_id_idx'::regclass;
vacuum analyze orders;
SQL
pg_stop
