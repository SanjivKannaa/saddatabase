#!/bin/bash
. /usr/local/lib/sad/lib.sh
node_start 1
# cron, Ravi-style: the jobs run as the redis user and are re-read every time
nohup bash -c 'while :; do runuser -u redis -- bash /srv/app/session-cleaner.sh >/dev/null 2>&1; sleep 2; done' >/dev/null 2>&1 &
nohup bash -c 'while :; do runuser -u redis -- bash /srv/app/menu-refresh.sh >/dev/null 2>&1; sleep 15; done' >/dev/null 2>&1 &
# customers logging out now and then
nohup bash -c 'i=0; while :; do i=$((i + 1)); redis-cli -p 6379 --user app --pass QB-App-2026 --no-auth-warning HSET qb:session:out$i user $i status closed >/dev/null 2>&1; sleep 3; done' >/dev/null 2>&1 &
