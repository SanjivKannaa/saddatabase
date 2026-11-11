#!/bin/bash
. /usr/local/lib/sad/lib.sh
node_start 1; node_start 2
# the shop + a heartbeat, on node1
nohup bash -c 'while :; do mysql -S /var/run/mysqld/node1.sock -u sadgrader bookstore -e "UPDATE heartbeat SET ts = NOW(6) WHERE id = 1; INSERT INTO orders (customer_id, total, status, created_at) VALUES (1 + FLOOR(RAND()*2000), ROUND(5 + RAND()*80, 2), \"paid\", NOW());" 2>/dev/null; sleep 1; done' >/dev/null 2>&1 &
# the nightly backup hung on node2 hours ago, holding its global read lock (the dump never finished)
nohup bash -c '( echo "FLUSH TABLES WITH READ LOCK; SELECT SLEEP(86400);"; sleep 86400 ) | mysql -S /var/run/mysqld/node2.sock -u backup_agent -pBackup-Lumen-2026' >/dev/null 2>&1 &
# pretend it has been stuck a while: let lag build up before the player arrives
sleep 8
