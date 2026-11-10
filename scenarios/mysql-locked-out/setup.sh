#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
db_start
sql <<'SQL'
create database billing;
use billing;
create table accounts (id int auto_increment primary key, name varchar(50), balance decimal(12,2));
set session cte_max_recursion_depth = 10000;
insert into accounts (name, balance) with recursive n(i) as (select 1 union all select i+1 from n where i < 777) select concat('acct ', i), rand()*1000 from n;
create role billing_reader;
grant select on billing.* to billing_reader;
create user 'app'@'%' identified by 'S4fe-pass' password expire account lock;
grant billing_reader to 'app'@'%';
SQL
db_stop
