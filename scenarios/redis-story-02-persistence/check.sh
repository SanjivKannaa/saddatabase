#!/bin/bash
. /usr/local/lib/sad/lib.sh
export SAD_USER=admin SAD_PASS=QB-Admin-2026
[ "$(rn 1 PING 2>&1)" = PONG ] || fail "node1 isn't answering (or admin / QB-Admin-2026 can't log in)"
# the data first
n=$(rn 1 DBSIZE)
if ! [ "$n" -ge 1000 ] 2>/dev/null; then
  [ "$(rn 1 CONFIG GET appendonly | tail -1)" = yes ] && [ "${n:-0}" -lt 500 ] && fail "node1 has only $n keys and the AOF is on: it was restarted with appendonly yes and loaded an empty AOF, dropping everything that was in memory"
  fail "node1 has only $n keys: last night it had 6701 (see /backups/redis)"
fi
cut -d' ' -f1 /opt/sad/expected.digest > /tmp/sad-keys
xargs -a /tmp/sad-keys redis-cli -p 6379 --user admin --pass QB-Admin-2026 --no-auth-warning DEBUG DIGEST-VALUE 2>&1 | paste -d' ' /tmp/sad-keys - > /tmp/sad-got
missing=$(awk '$2 == "0000000000000000000000000000000000000000"' /tmp/sad-got | wc -l)
if [ "$missing" != 0 ]; then
  m=$(awk '$2 ~ /^0+$/ && ($1 ~ /^qb:session:m/ || $1 ~ /^qb:user:20[0-5][0-9]$/) {c++} END {print c+0}' /tmp/sad-got)
  [ "$m" -gt 0 ] && fail "$m of this morning's keys are gone (e.g. $(awk '$2 ~ /^0+$/ && $1 ~ /^qb:session:m/ {print $1; exit}' /tmp/sad-got)): loading the backup onto node1 replaced its whole dataset"
  fail "$missing keys from last night's backup are still missing on node1 (e.g. $(awk '$2 ~ /^0+$/ {print $1; exit}' /tmp/sad-got))"
fi
diff=$(diff /opt/sad/expected.digest /tmp/sad-got | grep -c '^>')
if [ "$diff" != 0 ]; then
  k=$(diff /opt/sad/expected.digest /tmp/sad-got | sed -n 's/^> \([^ ]*\) .*/\1/p' | head -1)
  case $k in qb:cart:[0-9]|qb:cart:[0-9][0-9]|qb:cart:100|qb:orders:pending) fail "$diff keys don't match, e.g. $k: it was changed this morning, and the backup's older version overwrote it" ;; esac
  fail "$diff keys don't have the right contents, e.g. $k"
fi
nottl=0
for k in $(grep '^qb:session:' /tmp/sad-keys | head -400); do [ "$(rn 1 TTL "$k")" -gt 0 ] || nottl=$((nottl + 1)); done
[ "$nottl" = 0 ] || fail "$nottl restored sessions have no expiry any more: they'd live forever (restore with their TTL)"
# then a crash
[ "$(rn 1 CONFIG GET appendonly | tail -1)" = yes ] || fail "the append-only file is off: with RDB snapshots alone, a crash loses everything since the last one"
for i in $(seq 60); do rn 1 INFO persistence | grep -q '^aof_rewrite_in_progress:0' && break; sleep 0.5; done
probe="qb:grader:$(date +%s%N)"
rn 1 SET "$probe" crash-test >/dev/null
sleep 2
node_kill 1; node_start 1
[ "$(rn 1 PING 2>&1)" = PONG ] || fail "node1 doesn't come back after a crash (kill -9): tail /var/log/redis/node1.log"
[ "$(rn 1 CONFIG GET appendonly | tail -1)" = yes ] || fail "after a crash node1 started with appendonly no: the setting wasn't saved to node1.conf (CONFIG REWRITE)"
[ "$(rn 1 GET "$probe")" = crash-test ] || fail "a key written 2 s before the crash is gone after it"
n2=$(rn 1 DBSIZE)
[ "$n2" -ge "$n" ] || fail "node1 had $n keys before the crash and $n2 after"
rn 1 DEL "$probe" >/dev/null
pass "last night's keys are back (today's untouched, sessions still expire), and node1 survives kill -9 with $n2 keys"
