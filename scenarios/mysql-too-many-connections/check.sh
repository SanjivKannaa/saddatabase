#!/bin/bash
. /usr/local/lib/sad/lib.sh
q "select 1" | grep -q 1 || fail "MySQL is not running"
up=$(q "show global status like 'Uptime'" | awk '{print $2}'); age=$(( $(date +%s) - $(stat -c %Y /run/sad-ready) ))
[ "$up" -ge $((age - 5)) ] || fail "MySQL was restarted; the task was to fix it live"
out=$(mysql -u web -pW3b-Lumen -N shop -e 'select 42' 2>&1 | grep -v 'Using a password')
[ "$out" = 42 ] || fail "web still can't connect: $out"
lim=$(q "select max_user_connections from mysql.user where user='reporting' and host='localhost'")
[ "${lim:-0}" -ge 1 ] && [ "$lim" -le 5 ] || fail "reporting can still open ${lim:-unlimited} connections (0 = unlimited)"
pass "web connects again, and reporting is capped at $lim connections"
