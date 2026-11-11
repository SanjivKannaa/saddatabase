#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
for n in 1 2; do node_init $n "gtid_mode = ON" "enforce_gtid_consistency = ON" "performance_schema = ON" "performance-schema-instrument = 'wait/lock/metadata/sql/mdl=ON'"; done
ns 1 -e "CREATE USER 'repl'@'127.0.0.1' IDENTIFIED BY 'Repl-Lumen-2026'; GRANT REPLICATION SLAVE ON *.* TO 'repl'@'127.0.0.1';"
ns 2 -e "CHANGE REPLICATION SOURCE TO SOURCE_HOST='127.0.0.1', SOURCE_PORT=3306, SOURCE_USER='repl', SOURCE_PASSWORD='Repl-Lumen-2026', SOURCE_AUTO_POSITION=1, GET_SOURCE_PUBLIC_KEY=1, SOURCE_CONNECT_RETRY=2; START REPLICA; SET PERSIST super_read_only = ON;"
ns 1 <<'SQL'
CREATE DATABASE bookstore;
USE bookstore;
CREATE TABLE books (
  id INT AUTO_INCREMENT PRIMARY KEY,
  isbn CHAR(10) NOT NULL,
  title VARCHAR(200) NOT NULL,
  author VARCHAR(120) NOT NULL,
  price DECIMAL(8,2) NOT NULL,
  stock INT NOT NULL,
  description VARCHAR(400) NOT NULL,
  updated_at DATETIME NOT NULL
);
SET SESSION cte_max_recursion_depth = 500000;
INSERT INTO books (isbn, title, author, price, stock, description, updated_at)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 400000)
SELECT LPAD(i, 10, '0'), CONCAT('Book number ', i), CONCAT('Author ', i % 5000), ROUND(3 + RAND()*60, 2), FLOOR(RAND()*40),
       REPEAT('A fine used copy, lightly read. ', 8), NOW() - INTERVAL FLOOR(RAND()*900) DAY FROM n;
SQL
gt=$(nq 1 "select @@gtid_executed" | tr -d '\n'); [ "$(nq 2 "select wait_for_executed_gtid_set('$gt', 300)")" = 0 ]
nq 1 "select count(*) from bookstore.books" > /opt/sad/books.count
node_stop 2; node_stop 1
rm -f /usr/local/bin/node3
mkdir -p /var/log/app && chown mysql:mysql /var/log/app
