#!/bin/bash
. /usr/local/lib/sad/lib.sh
node_start 1; node_start 2
: > /var/log/app/stalls.log; chown mysql:mysql /var/log/app/stalls.log
# the app: constant small updates to books. A write that waits more than 5 s for a lock is a stall
# (measured as a lock timeout, not wall-clock time, so a busy CPU doesn't count as a freeze).
nohup bash -c '
while :; do
  out=$(mysql -S /var/run/mysqld/node1.sock -u sadgrader bookstore -e "SET SESSION lock_wait_timeout = 5, innodb_lock_wait_timeout = 5; UPDATE books SET stock = GREATEST(stock - 1, 0), updated_at = NOW() WHERE id = 1 + FLOOR(RAND()*400000)" 2>&1)
  case $out in *"Lock wait timeout"*|*"lock wait timeout"*) echo "$(date "+%F %T") write to books blocked by a lock for more than 5 s" >> /var/log/app/stalls.log ;; esac
  sleep 0.2
done' >/dev/null 2>&1 &
