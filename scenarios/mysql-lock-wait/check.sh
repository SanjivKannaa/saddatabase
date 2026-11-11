#!/bin/bash
. /usr/local/lib/sad/lib.sh
q "select 1" | grep -q 1 || fail "MySQL is not running"
up=$(q "show global status like 'Uptime'" | awk '{print $2}'); age=$(( $(date +%s) - $(stat -c %Y /run/sad-ready) ))
[ "$up" -ge $((age - 5)) ] || fail "MySQL was restarted; the task was to fix it live"
out=$(mysql -u sadgrader -N store -e "SET SESSION innodb_lock_wait_timeout = 3; UPDATE inventory SET qty = qty WHERE sku = 'A-100'; SELECT 'ok'" 2>&1)
[ "$out" = ok ] || fail "updates to A-100 still wait for a lock: $out"
w=$(q "select @@global.wait_timeout"); i=$(q "select @@global.interactive_timeout")
[ "$w" -le 600 ] || fail "wait_timeout is ${w}s: idle sessions live longer than 10 minutes"
[ "$i" -le 600 ] || fail "interactive_timeout is ${i}s: idle interactive sessions (like a forgotten mysql prompt) live longer than 10 minutes"
grep -qs '"wait_timeout"' /srv/mysql/mysqld-auto.cnf || grep -qsE '^\s*wait_timeout' /etc/my.cnf /etc/mysql/conf.d/*.cnf || fail "wait_timeout isn't persistent"
pass "A-100 updates go through, and idle sessions are closed after ${w}s (interactive ${i}s), persistently"
