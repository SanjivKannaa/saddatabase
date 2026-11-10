#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
db_start
sql <<'SQL'
create database inventory;
use inventory;
create table items (id int auto_increment primary key, sku varchar(20) unique, qty int);
set session cte_max_recursion_depth = 10000;
insert into items (sku, qty) with recursive n(i) as (select 1 union all select i+1 from n where i < 5000) select concat('SKU-', i), floor(rand()*100) from n;
SQL
db_stop
cat > /etc/mysql/conf.d/legacy-tuning.cnf <<'CNF'
# copied from db-legacy-01 (MySQL 5.7) -- tuned by dave, 2019
[mysqld]
max_connections   = 300
query_cache_type  = 1
query_cache_size  = 64M
log-error         = /var/log/mysql-legacy/error.log
CNF
chown mysql:mysql /etc/mysql/conf.d/legacy-tuning.cnf
