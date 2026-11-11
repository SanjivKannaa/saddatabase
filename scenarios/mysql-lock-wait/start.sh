#!/bin/bash
. /usr/local/lib/sad/lib.sh
db_start
nohup bash -c '( echo "BEGIN; UPDATE inventory SET reserved = reserved + 1 WHERE sku LIKE '\''A-1%'\'';"; sleep 86400 ) | mysql -u batch -pB4tch-Lumen store' >/dev/null 2>&1 &
sleep 2
