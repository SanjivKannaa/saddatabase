#!/bin/bash
. /usr/local/lib/sad/lib.sh
db_start
for i in $(seq 1 32); do
  nohup bash -c '( echo "select 1;"; sleep 86400 ) | mysql -u reporting -pR3port-Lumen shop' >/dev/null 2>&1 &
done
sleep 3
