#!/bin/bash
. /usr/local/lib/sad/lib.sh
q "select 1" | grep -q 1 || fail "MySQL is not running"
out=$(mysql -h 127.0.0.1 -u app -p'S4fe-pass' billing -N -B -e 'select count(*) from accounts' 2>&1 | grep -v 'Using a password')
[ "$out" = "777" ] || fail "the app still can't read accounts: $out"
g=$(q "select count(*) from mysql.user where user='app' and (Select_priv='Y' or Super_priv='Y' or Insert_priv='Y' or Create_user_priv='Y')")
[ "$g" = "0" ] || fail "app has global privileges; it should only read billing"
pass "the app connects and reads 777 accounts, with no global privileges"
