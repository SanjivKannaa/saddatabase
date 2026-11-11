#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
node_init 1 "gtid_mode = ON" "enforce_gtid_consistency = ON"
node_init 2
sed -i 's/^server_id .*/server_id                 = 1/' /etc/mysql/nodes/node2.cnf
echo "gtid_mode                 = OFF" >> /etc/mysql/nodes/node2.cnf
ns 1 <<'SQL'
CREATE DATABASE bookstore;
USE bookstore;
CREATE TABLE customers (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(80), email VARCHAR(120), loyalty_points INT NOT NULL DEFAULT 0);
CREATE TABLE orders (id INT AUTO_INCREMENT PRIMARY KEY, customer_id INT NOT NULL, total DECIMAL(10,2) NOT NULL, status VARCHAR(12) NOT NULL, created_at DATETIME NOT NULL, KEY (customer_id));
SET SESSION cte_max_recursion_depth = 20000;
INSERT INTO customers (name, email, loyalty_points) WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 2000) SELECT CONCAT('Reader ', i), CONCAT('reader', i, '@mail.test'), FLOOR(RAND()*100) FROM n;
INSERT INTO orders (customer_id, total, status, created_at) WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 20000) SELECT 1 + FLOOR(RAND()*2000), ROUND(5 + RAND()*80, 2), 'shipped', NOW() - INTERVAL FLOOR(RAND()*400) DAY FROM n;
SQL
node_stop 1; node_stop 2
rm -f /usr/local/bin/node3
