#!/bin/bash
. /usr/local/lib/sad/lib.sh
node_start 1; node_start 2
# the app: an order every half second (fails while node1 refuses writes)
nohup bash -c 'i=0; while :; do i=$((i + 1)); redis-cli -p 6379 --user app --pass QB-App-2026 --no-auth-warning RPUSH qb:orders:pending "order-$(date +%s)-$i" >/dev/null 2>&1; sleep 0.5; done' >/dev/null 2>&1 &
