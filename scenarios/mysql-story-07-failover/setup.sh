#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
for n in 1 2 3; do node_init $n "gtid_mode = ON" "enforce_gtid_consistency = ON"; done
ns 1 <<'SQL'
CREATE USER 'repl'@'127.0.0.1' IDENTIFIED BY 'Repl-Lumen-2026';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'127.0.0.1';
CREATE USER 'app'@'127.0.0.1' IDENTIFIED BY 'App-Lumen-2026';
SQL
for n in 2 3; do ns $n -e "CHANGE REPLICATION SOURCE TO SOURCE_HOST='127.0.0.1', SOURCE_PORT=3306, SOURCE_USER='repl', SOURCE_PASSWORD='Repl-Lumen-2026', SOURCE_AUTO_POSITION=1, GET_SOURCE_PUBLIC_KEY=1, SOURCE_CONNECT_RETRY=5; START REPLICA; SET PERSIST super_read_only = ON;"; done
ns 1 <<'SQL'
CREATE DATABASE bookstore;
USE bookstore;
CREATE TABLE orders (id INT AUTO_INCREMENT PRIMARY KEY, customer_id INT NOT NULL, total DECIMAL(10,2) NOT NULL, status VARCHAR(12) NOT NULL, created_at DATETIME NOT NULL);
GRANT SELECT, INSERT, UPDATE, DELETE ON bookstore.* TO 'app'@'127.0.0.1';
SET SESSION cte_max_recursion_depth = 20000;
INSERT INTO orders (customer_id, total, status, created_at) WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 10000) SELECT 1 + FLOOR(RAND()*2000), ROUND(5 + RAND()*80, 2), 'shipped', NOW() - INTERVAL FLOOR(RAND()*400) DAY FROM n;
SQL
for i in $(seq 1 1000); do echo "INSERT INTO orders (customer_id, total, status, created_at) VALUES (1 + FLOOR(RAND()*2000), ROUND(5 + RAND()*80, 2), 'paid', NOW());"; done | ns 1 bookstore
gt=$(nq 1 "select @@gtid_executed" | tr -d '\n'); for n in 2 3; do [ "$(nq $n "select wait_for_executed_gtid_set('$gt', 60)")" = 0 ]; done
# node3 loses its connection to node1 a few minutes before the crash...
ns 3 -e "STOP REPLICA IO_THREAD"
# ...and the busiest minutes of Black Friday only reach node2
for i in $(seq 1 50); do echo "INSERT INTO orders (customer_id, total, status, created_at) VALUES (1 + FLOOR(RAND()*2000), ROUND(80 + RAND()*200, 2), 'paid', NOW());"; done | ns 1 bookstore
gt=$(nq 1 "select @@gtid_executed" | tr -d '\n'); [ "$(nq 2 "select wait_for_executed_gtid_set('$gt', 60)")" = 0 ]
echo "$gt" > /opt/sad/node1.gtids
nq 1 "select count(*) from bookstore.orders" > /opt/sad/node1.orders
# 09:14: node1's disk dies (its data goes somewhere the player can't reach)
node_stop 1
mv /srv/mysql/node1 /opt/sad/node1-disk
echo "host unreachable: disk failure on db-01 (hosting ticket #48213)" > /etc/mysql/nodes/node1.dead
ns 3 -e "START REPLICA IO_THREAD"
node_stop 2; node_stop 3
printf '# bookstore app database connection\nDB_HOST=127.0.0.1\nDB_PORT=3306\nDB_USER=app\nDB_NAME=bookstore\n' > /srv/app/db.env
chown mysql:mysql /srv/app/db.env
