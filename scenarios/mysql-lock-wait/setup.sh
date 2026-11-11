#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
db_start
sql <<'SQL'
CREATE DATABASE store;
USE store;
CREATE TABLE inventory (sku VARCHAR(20) PRIMARY KEY, qty INT NOT NULL, reserved INT NOT NULL DEFAULT 0);
SET SESSION cte_max_recursion_depth = 5000;
INSERT INTO inventory (sku, qty) WITH RECURSIVE n(i) AS (SELECT 100 UNION ALL SELECT i+1 FROM n WHERE i < 999) SELECT CONCAT('A-', i), 100 FROM n;
CREATE USER 'batch'@'localhost' IDENTIFIED BY 'B4tch-Lumen';
GRANT SELECT, UPDATE ON store.* TO 'batch'@'localhost';
SQL
db_stop
