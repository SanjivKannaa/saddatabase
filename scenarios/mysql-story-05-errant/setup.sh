#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
node_init 1 "gtid_mode = ON" "enforce_gtid_consistency = ON"
node_init 2 "gtid_mode = ON" "enforce_gtid_consistency = ON"
ns 1 <<'SQL'
CREATE USER 'repl'@'127.0.0.1' IDENTIFIED BY 'Repl-Lumen-2026';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'127.0.0.1';
SQL
ns 2 -e "RESET BINARY LOGS AND GTIDS; CHANGE REPLICATION SOURCE TO SOURCE_HOST='127.0.0.1', SOURCE_PORT=3306, SOURCE_USER='repl', SOURCE_PASSWORD='Repl-Lumen-2026', SOURCE_AUTO_POSITION=1, GET_SOURCE_PUBLIC_KEY=1; START REPLICA;"
ns 1 <<'SQL'
CREATE DATABASE bookstore;
USE bookstore;
CREATE TABLE customers (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(80), email VARCHAR(120), loyalty_points INT NOT NULL DEFAULT 0);
CREATE TABLE orders (id INT AUTO_INCREMENT PRIMARY KEY, customer_id INT NOT NULL, total DECIMAL(10,2) NOT NULL, status VARCHAR(12) NOT NULL, created_at DATETIME NOT NULL, KEY (customer_id));
SET SESSION cte_max_recursion_depth = 20000;
INSERT INTO customers (name, email, loyalty_points) WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 2000) SELECT CONCAT('Reader ', i), CONCAT('reader', i, '@mail.test'), FLOOR(RAND()*100) FROM n;
INSERT INTO orders (id, customer_id, total, status, created_at) WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 15000) SELECT 885000 + i, 1 + FLOOR(RAND()*2000), ROUND(5 + RAND()*80, 2), 'shipped', NOW() - INTERVAL FLOOR(RAND()*400) DAY FROM n;
SQL
gt=$(nq 1 "select @@gtid_executed" | tr -d '\n'); nq 2 "select wait_for_executed_gtid_set('$gt', 30)" >/dev/null
# yesterday: Marco writes on the replica (two errant GTIDs on node2)
ns 2 bookstore <<'SQL'
INSERT INTO orders (id, customer_id, total, status, created_at) VALUES (900001, 314, 24.99, 'paid', NOW() - INTERVAL 1 DAY);
UPDATE customers SET email = 'reader777@gmial.test' WHERE id = 777;
SQL
# today: the shop creates the real order 900001 on node1 -> duplicate key on node2, replication stops
ns 1 bookstore <<'SQL'
INSERT INTO orders (id, customer_id, total, status, created_at) VALUES (900001, 1201, 61.40, 'paid', NOW());
INSERT INTO orders (customer_id, total, status, created_at) VALUES (88, 15.00, 'paid', NOW()), (1999, 42.00, 'paid', NOW());
UPDATE orders SET status = 'shipped' WHERE id BETWEEN 899990 AND 900000;
SQL
for i in $(seq 30); do [ "$(rs 2 Replica_SQL_Running)" = No ] && break; sleep 0.5; done
[ "$(rs 2 Replica_SQL_Running)" = No ] || { echo "setup: replication did not break"; exit 1; }
node_stop 1; node_stop 2
rm -f /usr/local/bin/node3
