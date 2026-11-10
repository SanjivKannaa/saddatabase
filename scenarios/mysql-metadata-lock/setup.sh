#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
db_start
sql <<'SQL'
create database shop;
use shop;
create table products (id int auto_increment primary key, name varchar(80), price decimal(10,2));
set session cte_max_recursion_depth = 10000;
insert into products (name, price) with recursive n(i) as (select 1 union all select i+1 from n where i < 1000) select concat('product ', i), rand()*100 from n;
create user reporting@'127.0.0.1' identified by 'r3port'; grant select on shop.* to reporting@'127.0.0.1';
create user migrator@'127.0.0.1' identified by 'm1grate'; grant all on shop.* to migrator@'127.0.0.1';
create user web@'127.0.0.1' identified by 'w3b'; grant select on shop.* to web@'127.0.0.1';
SQL
db_stop
