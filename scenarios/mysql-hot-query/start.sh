#!/bin/bash
. /usr/local/lib/sad/lib.sh
db_start
# the app: one connection each, running its queries in a loop
nohup bash -c 'while :; do echo "SELECT id, total FROM orders WHERE coupon_code = '\''BF2026-$((RANDOM % 5000))'\'';"; sleep 0.3; done | mysql -u sadgrader shop' >/dev/null 2>&1 &
nohup bash -c 'while :; do echo "SELECT * FROM orders WHERE id = $((RANDOM * 9 % 300000 + 1)); SELECT name FROM customers WHERE email = '\''reader$((RANDOM % 50000))@mail.test'\'';"; sleep 0.05; done | mysql -u sadgrader shop' >/dev/null 2>&1 &
nohup bash -c 'while :; do echo "SELECT COUNT(*) FROM orders WHERE status = '\''pending'\'';"; sleep 2; done | mysql -u sadgrader shop' >/dev/null 2>&1 &
nohup bash -c 'while :; do echo "SELECT COUNT(*) FROM orders WHERE notes LIKE '\''%wrap%'\'';"; sleep 60; done | mysql -u sadgrader shop' >/dev/null 2>&1 &
sleep 5
