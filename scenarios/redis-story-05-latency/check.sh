#!/bin/bash
. /usr/local/lib/sad/lib.sh
export SAD_USER=admin SAD_PASS=QB-Admin-2026
[ "$(rn 1 PING 2>&1)" = PONG ] || fail "node1 isn't answering (or admin can't log in)"
keys_calls() { rn 1 INFO commandstats | tr -d '\r' | sed -n 's/^cmdstat_keys:calls=\([0-9]*\),.*/\1/p'; }
for i in $(seq 20); do rn 1 HSET qb:session:grader-$i user $i status closed >/dev/null; done
rn 1 HSET qb:session:grader-active user 1 status active >/dev/null
rn 1 CONFIG SET slowlog-log-slower-than 5000 >/dev/null
rn 1 CONFIG SET slowlog-max-len 128 >/dev/null
rn 1 SLOWLOG RESET >/dev/null
k0=$(keys_calls); t0=$(date +%s)
echo "watching node1 for 18 s..."
sleep 18
k1=$(keys_calls)
[ "${k1:-0}" = "${k0:-0}" ] || fail "KEYS ran $(( ${k1:-0} - ${k0:-0} )) times in 18 s: it walks the whole keyspace and blocks everyone (use SCAN)"
entries=$(rn 1 SLOWLOG LEN)
if [ "${entries:-0}" -gt 0 ]; then
  top=$(rn 1 --json SLOWLOG GET 128 | jq -r 'map({c: ((.[3][0] // "?") + " " + (.[3][1] // "")), us: .[2]}) | group_by(.c) | map("\(.[0].c) (\(((map(.us) | max) / 100 | floor) / 10) ms, \(length)x)") | join(", ")')
  fail "$entries command(s) took over 5 ms while the grader watched: $top"
fi
gone=0; for i in $(seq 20); do [ "$(rn 1 EXISTS qb:session:grader-$i)" = 0 ] && gone=$((gone + 1)); done
[ "$gone" = 20 ] || fail "the session cleaner isn't working: $((20 - gone)) of 20 closed sessions are still there after 18 s"
[ "$(rn 1 EXISTS qb:session:grader-active)" = 1 ] || fail "the session cleaner deleted an ACTIVE session"
rn 1 DEL qb:session:grader-active >/dev/null
b=$(rn 1 HGET qb:menu:all _built)
[ "${b:-0}" -ge "$t0" ] 2>/dev/null || fail "the menu wasn't rebuilt while the grader watched (_built = ${b:-none}): menu-refresh.sh must keep working"
for i in $(seq 10); do n=$(rn 1 HLEN qb:menu:all); [ "${n:-0}" -ge 250001 ] && break; sleep 0.5; done
[ "${n:-0}" -ge 250001 ] || fail "qb:menu:all has $n fields after a rebuild, expected 250000 dishes + _built"
pass "18 s without a command over 5 ms or a single KEYS; sessions are cleaned and the menu rebuilt"
