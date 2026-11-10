#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
db_start
sql <<'SQL'
create database shop;
use shop;
create table orders (
  id int auto_increment primary key,
  customer_ref varchar(20) not null,
  status varchar(12) not null,
  total decimal(10,2),
  created_at datetime not null,
  index idx_customer_ref (customer_ref)
);
set session cte_max_recursion_depth = 500000;
insert into orders (customer_ref, status, total, created_at)
with recursive n(i) as (select 1 union all select i+1 from n where i < 400000)
select cast(floor(1 + rand()*9999) as char), elt(1 + floor(rand()*4), 'pending','paid','shipped','delivered'),
       rand()*300, now() - interval floor(rand()*730*24*60) minute from n;
analyze table orders;
SQL
db_stop
