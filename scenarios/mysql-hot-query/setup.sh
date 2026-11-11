#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
db_start
sql <<'SQL'
CREATE DATABASE shop;
USE shop;
CREATE TABLE customers (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(80), email VARCHAR(120), KEY (email));
CREATE TABLE orders (
  id INT AUTO_INCREMENT PRIMARY KEY, customer_id INT NOT NULL, status VARCHAR(12) NOT NULL, coupon_code VARCHAR(20),
  total DECIMAL(10,2) NOT NULL, notes VARCHAR(200), created_at DATETIME NOT NULL, KEY (customer_id), KEY (status));
SET SESSION cte_max_recursion_depth = 400000;
INSERT INTO customers (name, email) WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 50000) SELECT CONCAT('Reader ', i), CONCAT('reader', i, '@mail.test') FROM n;
INSERT INTO orders (customer_id, status, coupon_code, total, notes, created_at)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 300000)
SELECT 1 + FLOOR(RAND()*50000), ELT(1 + FLOOR(RAND()*4), 'pending','paid','shipped','delivered'),
       IF(RAND() < 0.3, CONCAT('BF2026-', FLOOR(RAND()*5000)), NULL), ROUND(5 + RAND()*80, 2),
       IF(RAND() < 0.1, 'gift wrap please', NULL), NOW() - INTERVAL FLOOR(RAND()*700) DAY FROM n;
ANALYZE TABLE orders, customers;
SQL
db_stop
