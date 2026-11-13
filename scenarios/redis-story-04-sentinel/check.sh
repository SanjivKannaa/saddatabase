#!/bin/bash
. /usr/local/lib/sad/lib.sh
export SAD_USER=admin SAD_PASS=QB-Admin-2026
info() { rp $1 INFO replication | tr -d '\r' | sed -n "s/^$2://p"; }
sm() { redis-cli -p $1 SENTINEL master quickbite 2>/dev/null | awk -v k="$2" 'p {print; exit} $0 == k {p = 1}'; }
master() { redis-cli -p 26379 SENTINEL get-master-addr-by-name quickbite 2>/dev/null | tail -1; }
for s in 26379 26380 26381; do
  [ "$(redis-cli -p $s PING 2>&1)" = PONG ] || fail "no Sentinel answers on port $s"
  [ -n "$(redis-cli -p $s SENTINEL master quickbite 2>/dev/null | head -1)" ] || fail "the Sentinel on $s doesn't monitor a master named 'quickbite'"
done
for s in 26379 26380 26381; do
  [ "$(sm $s quorum)" = 2 ] || fail "Sentinel $s: quorum is $(sm $s quorum), not 2"
  d=$(sm $s down-after-milliseconds); [ "${d:-99999}" -le 5000 ] || fail "Sentinel $s waits ${d} ms before calling the primary down: 5000 at most"
  for i in $(seq 20); do [ "$(sm $s num-other-sentinels)" = 2 ] && [ "$(sm $s num-slaves)" = 2 ] && break; sleep 0.5; done
  [ "$(sm $s num-other-sentinels)" = 2 ] || fail "Sentinel $s sees $(sm $s num-other-sentinels) other Sentinels, not 2 (they find each other through the primary: can they log in to it?)"
  [ "$(sm $s num-slaves)" = 2 ] || fail "Sentinel $s sees $(sm $s num-slaves) replicas, not 2"
  [[ "$(sm $s flags)" == master ]] || fail "Sentinel $s flags the primary as '$(sm $s flags)' (auth problems? tail /var/log/redis/sentinel*.log)"
done
[[ "$(redis-cli -p 26379 SENTINEL ckquorum quickbite 2>&1)" == OK* ]] || fail "SENTINEL ckquorum: $(redis-cli -p 26379 SENTINEL ckquorum quickbite 2>&1)"
old=$(master); case $old in 6379) on=1 ;; 6380) on=2 ;; 6381) on=3 ;; *) fail "Sentinel reports the primary on port '${old}'" ;; esac
[ "$(info $old role)" = master ] || fail "port $old isn't actually a primary"
# kill the primary
node_kill $on
new=$old
for i in $(seq 90); do new=$(master); [ "$new" != "$old" ] && [ "$(info "$new" role 2>/dev/null)" = master ] && break; sleep 0.5; done
[ "$new" != "$old" ] || fail "node$on (port $old) was killed and no replica was promoted within 45 s (tail /var/log/redis/sentinel1.log)"
[ "$(info "$new" role)" = master ] || fail "Sentinel says the primary is $new, but it isn't a primary"
for p in 6379 6380 6381; do
  [ $p = $old ] || [ $p = $new ] && continue
  for i in $(seq 40); do [ "$(info $p master_port)" = "$new" ] && [ "$(info $p master_link_status)" = up ] && break; sleep 0.5; done
  [ "$(info $p master_port)" = "$new" ] && [ "$(info $p master_link_status)" = up ] || fail "the other replica (port $p) doesn't follow the new primary $new"
done
for i in $(seq 20); do [ -n "$(awk -v t=$(($(date +%s) - 3)) -v p=$new '$1 >= t && $2 == p' /opt/sad/app.log)" ] && break; sleep 0.5; done
[ -n "$(awk -v t=$(($(date +%s) - 5)) -v p=$new '$1 >= t && $2 == p' /opt/sad/app.log)" ] || fail "the app isn't writing to the new primary ($new)"
# the old primary comes back
node_start $on
for i in $(seq 60); do [ "$(info $old role)" = slave ] && [ "$(info $old master_port)" = "$new" ] && [ "$(info $old master_link_status)" = up ] && break; sleep 0.5; done
[ "$(info $old role)" = slave ] && [ "$(info $old master_port)" = "$new" ] || fail "node$on came back but isn't a replica of the new primary $new (role $(info $old role))"
[ "$(info $old master_link_status)" = up ] || fail "node$on is now a replica of $new but its link is down: can it authenticate to the new primary? ($(grep -E 'NOAUTH|AUTH|NOPERM' /var/log/redis/node$on.log | tail -1 | cut -c1-120))"
pass "3 Sentinels, quorum 2: node$on was killed, port $new was promoted, the app followed and node$on rejoined as its replica"
