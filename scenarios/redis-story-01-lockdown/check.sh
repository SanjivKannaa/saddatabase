#!/bin/bash
. /usr/local/lib/sad/lib.sh
runuser -u redis -- /usr/local/lib/sad/svc status node1 | grep -q running || fail "node1 isn't running (sudo systemctl start redis-server@node1)"
runuser -u redis -- /usr/local/lib/sad/svc restart node1 >/dev/null || fail "node1 doesn't come back after a restart: tail /var/log/redis/node1.log"
out=$(redis-cli -p 6379 EXISTS qb:user:1 2>&1)
[[ "$out" == *NOAUTH* ]] || fail "an unauthenticated client can still run commands after a restart (EXISTS qb:user:1 -> '${out:0:60}')"
export SAD_USER=admin SAD_PASS=QB-Admin-2026
[ "$(rn 1 PING 2>&1)" = PONG ] || fail "can't log in as admin / QB-Admin-2026 after a restart"
[ "$(rn 1 ACL DRYRUN admin FLUSHALL 2>&1)" = OK ] || fail "admin can't run everything"
[[ "$(redis-cli -p 6379 --user default --pass '' --no-auth-warning PING 2>&1)" != PONG ]] || fail "the default user still works with an empty password"
rn 1 ACL GETUSER default | grep -qx off || fail "the default user isn't disabled ('off')"
for c in "GET qb:user:1" "HSET qb:cart:1 item:1 2" "SUBSCRIBE qb:orders" "SCAN 0 MATCH qb:*"; do
  r=$(rn 1 ACL DRYRUN app $c 2>&1); [ "$r" = OK ] || fail "app can't run '$c': $r"
done
for c in "GET billing:secret" "FLUSHALL" "KEYS *" "CONFIG GET *" "DEBUG SLEEP 0" "SUBSCRIBE __keyspace@0__:x" "ACL LIST"; do
  r=$(rn 1 ACL DRYRUN app $c 2>&1); [ "$r" = OK ] && fail "app is allowed to run '$c': only qb:* keys, nothing @dangerous"
done
r=$(redis-cli -p 6379 --user app --pass QB-App-2026 --no-auth-warning SET qb:grader:probe 1 2>&1)
[ "$r" = OK ] || fail "app / QB-App-2026 can't log in and write qb:* keys: $r"
rn 1 DEL qb:grader:probe >/dev/null
b=$(rn 1 CONFIG GET bind | tail -1)
for a in $b; do case ${a#-} in 127.0.0.1|::1|localhost) ;; *) fail "node1 still binds '$b': localhost only" ;; esac; done
[ "$(rn 1 CONFIG GET protected-mode | tail -1)" = yes ] || fail "protected-mode is off"
n=$(rn 1 DBSIZE)
[ "$n" -ge 6700 ] 2>/dev/null || fail "node1 has $n keys after the restart, it had 6701: data lost?"
pass "node1 is locked down: default off, admin and app (qb:* only, no @dangerous), localhost, protected mode, all after a restart"
