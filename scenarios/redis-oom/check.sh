#!/bin/bash
. /usr/local/lib/sad/lib.sh
r ping 2>/dev/null | grep -q PONG || fail "Redis is not running"
for i in 1 2 3; do out=$(r set "cache:product:graded-$i" "$(head -c 2000 /dev/zero | tr '\0' x)" 2>&1); [ "$out" = "OK" ] || fail "writes still fail: $out"; done
max=$(r config get maxmemory | tail -1); pol=$(r config get maxmemory-policy | tail -1)
[ "$max" -gt 0 ] && [ "$max" -le $((200*1024*1024)) ] || fail "maxmemory must be set and at most 200 MB (it is $max bytes)"
[[ "$pol" == allkeys-* ]] || fail "maxmemory-policy is $pol: the cache keys have no TTL, so a full cache will block writes again"
grep -qE "^maxmemory-policy +allkeys-" /etc/redis/redis.conf || fail "the running server is fixed, but /etc/redis/redis.conf still says otherwise: a restart brings the outage back"
pass "writes work, maxmemory=$((max/1024/1024))MB, policy $pol, and the config file agrees"
