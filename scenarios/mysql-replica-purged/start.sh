#!/bin/bash
. /usr/local/lib/sad/lib.sh
node_start 1; node_start 2
nohup bash -c 'while :; do mysql -S /var/run/mysqld/node1.sock -u sadgrader bookstore -e "INSERT INTO orders (customer_id, total, status, created_at) VALUES (1 + FLOOR(RAND()*2000), ROUND(5 + RAND()*80, 2), \"paid\", NOW())" 2>/dev/null; sleep 1; done' >/dev/null 2>&1 &
sleep 3
