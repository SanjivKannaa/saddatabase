#!/bin/bash
. /usr/local/lib/sad/lib.sh
db_start
m() { u=$1; p=$2; shift 2; ( echo "$*"; sleep infinity ) | mysql -h 127.0.0.1 -u "$u" -p"$p" shop >/dev/null 2>&1 & }
m reporting r3port "begin; select count(*) from products;"
sleep 1
m migrator m1grate "alter table products add column discount_pct int not null default 0;"
sleep 1
for i in 1 2 3; do m web w3b "select * from products where id = $i;"; done
sleep 1
