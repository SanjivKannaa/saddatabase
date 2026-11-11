#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
node_init 1 "gtid_mode = ON" "enforce_gtid_consistency = ON"
node_init 2 "gtid_mode = ON" "enforce_gtid_consistency = ON"
ns 1 <<'SQL'
CREATE USER 'repl'@'127.0.0.1' IDENTIFIED BY 'Repl-Lumen-2026';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'127.0.0.1';
SQL
ns 2 -e "CHANGE REPLICATION SOURCE TO SOURCE_HOST='127.0.0.1', SOURCE_PORT=3306, SOURCE_USER='repl', SOURCE_PASSWORD='Repl-Lumen-2026', SOURCE_AUTO_POSITION=1, GET_SOURCE_PUBLIC_KEY=1, SOURCE_CONNECT_RETRY=2; START REPLICA; SET PERSIST super_read_only = ON;"
ns 1 <<'SQL'
CREATE DATABASE bookstore;
USE bookstore;
CREATE TABLE orders (id INT AUTO_INCREMENT PRIMARY KEY, customer_id INT NOT NULL, total DECIMAL(10,2) NOT NULL, status VARCHAR(12) NOT NULL, created_at DATETIME NOT NULL);
CREATE TABLE customers (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(80), email VARCHAR(120));
SET SESSION cte_max_recursion_depth = 20000;
INSERT INTO customers (name, email) WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 2000) SELECT CONCAT('Reader ', i), CONCAT('reader', i, '@mail.test') FROM n;
INSERT INTO orders (customer_id, total, status, created_at) WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 10000) SELECT 1 + FLOOR(RAND()*2000), ROUND(5 + RAND()*80, 2), 'shipped', NOW() - INTERVAL FLOOR(RAND()*400) DAY FROM n;
SQL
gt=$(nq 1 "select @@gtid_executed" | tr -d '\n'); [ "$(nq 2 "select wait_for_executed_gtid_set('$gt', 60)")" = 0 ]
node_stop 2                                    # a week offline...
for b in 1 2 3; do
  ns 1 bookstore -e "INSERT INTO orders (customer_id, total, status, created_at) SELECT 1 + FLOOR(RAND()*2000), ROUND(5 + RAND()*80, 2), 'paid', NOW() FROM customers LIMIT 300; UPDATE customers SET email = CONCAT('new', id, '@mail.test') WHERE id % 50 = $b;"
  ns 1 -e "FLUSH BINARY LOGS"
done
last=$(nq 1 "show binary logs" | tail -1 | awk '{print $1}')
ns 1 -e "PURGE BINARY LOGS TO '$last'"         # ...while node1 purged what node2 would need
node_stop 1
