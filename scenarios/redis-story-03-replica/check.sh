#!/bin/bash
. /usr/local/lib/sad/lib.sh
export SAD_USER=admin SAD_PASS=QB-Admin-2026
info() { rn $1 INFO replication | tr -d '\r' | sed -n "s/^$2://p"; }
link_up() { for i in $(seq 30); do [ "$(info 2 master_link_status)" = up ] && [ "$(info 1 connected_slaves)" -ge 1 ] 2>/dev/null && return 0; sleep 0.5; done; return 1; }
[ "$(rn 1 PING 2>&1)" = PONG ] || fail "node1 isn't answering (or admin can't log in)"
[ "$(rn 2 PING 2>&1)" = PONG ] || fail "node2 isn't answering (or admin can't log in)"
[ "$(rn 1 CONFIG GET min-replicas-to-write | tail -1)" = 1 ] || fail "min-replicas-to-write isn't 1 on node1 any more: Maya wants to keep it"
[ "$(info 2 role)" = slave ] || fail "node2 isn't a replica (role: $(info 2 role))"
[ "$(info 2 master_port)" = 6379 ] || fail "node2 replicates from port $(info 2 master_port), not node1"
link_up || fail "node2's link to node1 is down ($(grep -E 'MASTER|AUTH|NOPERM|NOAUTH' /var/log/redis/node2.log | tail -1 | cut -c1-160))"
u=$(rn 2 CONFIG GET masteruser | tail -1)
[ -n "$u" ] && [ "$u" != default ] || fail "node2 doesn't authenticate as a dedicated user (masteruser is '${u:-empty}')"
[ "$u" != admin ] || fail "node2 replicates as admin: give replication its own user"
for c in "GET qb:user:1" "SET qb:x 1" "FLUSHALL" "INFO" "KEYS *"; do
  [ "$(rn 1 ACL DRYRUN "$u" $c 2>&1)" = OK ] && fail "the replication user '$u' can run '$c': it needs +psync +replconf +ping, nothing more"
done
r=$(rn 2 SET qb:grader:direct 1 2>&1)
[[ "$r" == READONLY* ]] || { rn 2 DEL qb:grader:direct >/dev/null; fail "a client can write to node2 directly (SET -> '$r'): replica-read-only"; }
probe="qb:grader:$(date +%s%N)"
r=$(redis-cli -p 6379 --user app --pass QB-App-2026 --no-auth-warning SET "$probe" 1 2>&1)
[ "$r" = OK ] || fail "the app still can't write to node1: $r"
for i in $(seq 10); do [ "$(rn 2 EXISTS "$probe")" = 1 ] && break; sleep 0.5; done
[ "$(rn 2 EXISTS "$probe")" = 1 ] || fail "a key written on node1 didn't reach node2 within 5 s"
# both restarted: does it all come back?
runuser -u redis -- /usr/local/lib/sad/svc restart node1 >/dev/null || fail "node1 doesn't come back after a restart"
runuser -u redis -- /usr/local/lib/sad/svc restart node2 >/dev/null || fail "node2 doesn't come back after a restart"
[ "$(info 2 role)" = slave ] && link_up || fail "after restarting both nodes, node2 isn't replicating node1 any more: CONFIG REWRITE on both? ($(grep -E 'MASTER|AUTH|NOPERM' /var/log/redis/node2.log | tail -1 | cut -c1-120))"
[[ "$(rn 2 SET qb:grader:direct 1 2>&1)" == READONLY* ]] || fail "after a restart node2 accepts writes again: replica-read-only isn't saved in node2.conf"
[ "$(redis-cli -p 6379 --user app --pass QB-App-2026 --no-auth-warning DEL "$probe" 2>&1)" = 1 ] || fail "after the restarts the app can't write to node1"
pass "node2 replicates node1 as '$u' (replication only), is read-only, node1 takes writes, and it all survives restarts"
