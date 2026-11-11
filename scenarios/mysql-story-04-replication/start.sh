#!/bin/bash
. /usr/local/lib/sad/lib.sh
node_start 1; node_start 2
# the shop: a steady trickle of orders on node1 (root process: the player can't stop it, only the server)
nohup bash -c 'while :; do mysql -S /var/run/mysqld/node1.sock -u sadgrader bookstore -e "INSERT INTO orders (customer_id, total, status, created_at) VALUES (1 + FLOOR(RAND()*2000), ROUND(5 + RAND()*80, 2), \"paid\", NOW()); UPDATE customers SET loyalty_points = loyalty_points + 1 WHERE id = 1 + FLOOR(RAND()*2000);" 2>/dev/null; sleep 1; done' >/dev/null 2>&1 &
