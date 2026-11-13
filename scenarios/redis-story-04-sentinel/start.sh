#!/bin/bash
. /usr/local/lib/sad/lib.sh
node_start 1; node_start 2; node_start 3
: > /opt/sad/app.log
# the app: ask a Sentinel for the primary, fall back to node1; one order every 0.3 s; log successes
nohup bash -c 'i=0; while :; do i=$((i + 1)); port=6379
  for s in 26379 26380 26381; do a=$(timeout 2 redis-cli -p $s SENTINEL get-master-addr-by-name quickbite 2>/dev/null | tail -1); [[ "$a" =~ ^[0-9]+$ ]] && { port=$a; break; }; done
  r=$(timeout 3 redis-cli -p $port --user app --pass QB-App-2026 --no-auth-warning RPUSH qb:orders:pending "order-$(date +%s)-$i" 2>/dev/null)
  [[ "$r" =~ ^[0-9]+$ ]] && echo "$(date +%s) $port" >> /opt/sad/app.log
  sleep 0.3; done' >/dev/null 2>&1 &
