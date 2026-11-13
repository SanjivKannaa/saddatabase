#!/bin/bash
. /usr/local/lib/sad/lib.sh
export SAD_USER=admin SAD_PASS=QB-Admin-2026
ci() { rp $1 CLUSTER INFO 2>/dev/null | tr -d '\r' | sed -n "s/^$2://p"; }
ri() { rp $1 INFO replication 2>/dev/null | tr -d '\r' | sed -n "s/^$2://p"; }
for p in 7001 7002 7003 7004 7005 7006; do
  [ "$(rp $p PING 2>&1)" = PONG ] || fail "nothing answers on port $p (or admin can't log in)"
  [ "$(rp $p INFO cluster | tr -d '\r' | sed -n 's/^cluster_enabled://p')" = 1 ] || fail "port $p isn't running in cluster mode (cluster-enabled is a startup setting)"
done
[ "$(ci 7001 cluster_known_nodes)" = 6 ] || fail "the cluster knows $(ci 7001 cluster_known_nodes) nodes, not 6"
[ "$(ci 7001 cluster_slots_assigned)" = 16384 ] || fail "only $(ci 7001 cluster_slots_assigned) of 16384 slots are assigned"
for i in $(seq 20); do [ "$(ci 7001 cluster_state)" = ok ] && break; sleep 0.5; done
[ "$(ci 7001 cluster_state)" = ok ] || fail "cluster_state is $(ci 7001 cluster_state)"
masters=0; replicas=0
for p in 7001 7002 7003 7004 7005 7006; do
  case $(ri $p role) in
    master) masters=$((masters + 1))
      [ "$(ri $p connected_slaves)" -ge 1 ] 2>/dev/null || fail "master on $p has no connected replica: can its replica authenticate? ($(grep -hE "NOAUTH|NOPERM" /var/log/redis/node[4-9].log | tail -1 | cut -c1-110))" ;;
    slave) replicas=$((replicas + 1))
      for i in $(seq 20); do [ "$(ri $p master_link_status)" = up ] && break; sleep 0.5; done
      [ "$(ri $p master_link_status)" = up ] || fail "the replica on $p can't sync with its master (link down: $(grep -E 'NOAUTH|NOPERM|AUTH' /var/log/redis/node$((p - 6997)).log | tail -1 | cut -c1-110))" ;;
  esac
done
[ $masters = 3 ] && [ $replicas = 3 ] || fail "the cluster has $masters masters and $replicas replicas, not 3 + 3"
# node1 untouched
want=$(cat /opt/sad/dbsize); n1=$(rn 1 DBSIZE)
[ "$n1" = "$want" ] || fail "node1 has $n1 keys, it had $want: the rollback plan is gone (import moves keys unless you --cluster-copy)"
# every key in the cluster
total=0
for p in 7001 7002 7003 7004 7005 7006; do [ "$(ri $p role)" = master ] && total=$((total + $(rp $p DBSIZE))); done
[ "$total" -ge "$want" ] || fail "the cluster's masters hold $total keys, node1 has $want"
mports=$(for p in 7001 7002 7003 7004 7005 7006; do [ "$(ri $p role)" = master ] && echo $p; done)
zero=0000000000000000000000000000000000000000
bad=0; nottl=0; checked=0
for k in $(rn 1 --scan --count 1000 | awk 'NR % 41 == 0' | head -150); do
  checked=$((checked + 1))
  a=$(rn 1 DEBUG DIGEST-VALUE "$k"); b=$zero
  for p in $mports; do d=$(rp $p DEBUG DIGEST-VALUE "$k" 2>/dev/null); [ -n "$d" ] && [ "$d" != $zero ] && { b=$d; break; }; done
  [ "$a" = "$b" ] || bad=$((bad + 1))
  if [[ $k == qb:session:* ]]; then t=$(rp 7001 -c TTL "$k"); [ "${t:--1}" -gt 0 ] || nottl=$((nottl + 1)); fi
done
[ "$bad" = 0 ] || fail "$bad of $checked sampled keys differ between node1 and the cluster"
[ "$nottl" = 0 ] || fail "$nottl sampled sessions lost their TTL in the cluster"
r=$(redis-cli -c -p 7002 --user app --pass QB-App-2026 --no-auth-warning SET qb:grader:probe 1 2>&1)
[ "$r" = OK ] || fail "the app user can't write qb:* keys through the cluster: $r"
[ "$(redis-cli -c -p 7003 --user app --pass QB-App-2026 --no-auth-warning GET qb:menu:7 2>&1)" = "$(rn 1 GET qb:menu:7)" ] || fail "the app user can't read qb:menu:7 through the cluster"
redis-cli -c -p 7002 --user app --pass QB-App-2026 --no-auth-warning DEL qb:grader:probe >/dev/null
pass "3 masters + 3 replicas, 16384 slots, cluster_state ok; all $want keys copied (sampled $checked: values and TTLs match); node1 untouched"
