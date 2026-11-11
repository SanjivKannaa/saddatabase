#!/bin/bash
. /usr/local/lib/sad/lib.sh
[ "$(nq 1 'select 1')" = 1 ] && [ "$(nq 2 'select 1')" = 1 ] || fail "node1 and node2 must both be running"
cd /srv/mysql/node1
listed=$(nq 1 "show binary logs" | awk '{print $1}')
for f in $listed; do [ -f "$f" ] || fail "the binlog index lists $f but the file is gone: binlogs were deleted by hand, so the server's view is broken"; done
need=$(rs 2 Source_Log_File)
older=$(echo "$listed" | awk -v n="$need" '$0 < n' | wc -l)
[ "$older" -eq 0 ] || fail "$older binlog file(s) older than $need are still there; node2 doesn't need them"
exp=$(nq 1 "select @@binlog_expire_logs_seconds")
[ "$exp" -ge 1 ] && [ "$exp" -le 604800 ] || fail "binlog_expire_logs_seconds is $exp: set it to at most 604800 (7 days)"
grep -qs '"binlog_expire_logs_seconds"' /srv/mysql/node1/mysqld-auto.cnf || grep -qsE '^\s*binlog_expire_logs_seconds\s*=\s*[1-9]' /etc/mysql/nodes/node1.cnf || fail "the expiry isn't persistent: a restart would bring back 'never expire'"
grep -qsE '^\s*binlog_expire_logs_seconds\s*=\s*0' /etc/mysql/nodes/node1.cnf && ! grep -qs '"binlog_expire_logs_seconds"' /srv/mysql/node1/mysqld-auto.cnf && fail "node1.cnf still says binlog_expire_logs_seconds = 0"
echo "resuming node2 to make sure it can still catch up..."
ns 2 -e "START REPLICA"
gt=$(nq 1 "select @@gtid_executed" | tr -d '\n')
r=$(nq 2 "select wait_for_executed_gtid_set('$gt', 60)")
err=$(rs 2 Last_IO_Error)
[ -n "$err" ] && fail "node2 can't resume: $(echo "$err" | cut -c1-160)"
[ "$r" = 0 ] || fail "node2 didn't catch up after resuming"
pass "only the binlogs node2 still needs remain ($(echo "$listed" | wc -l) files), expiry is ${exp}s and persistent, and node2 caught up"
