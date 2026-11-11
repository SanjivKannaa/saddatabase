#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
db_start
sql <<'SQL'
CREATE DATABASE shop;
CREATE USER 'web'@'localhost' IDENTIFIED BY 'W3b-Lumen';
CREATE USER 'reporting'@'localhost' IDENTIFIED BY 'R3port-Lumen';
GRANT SELECT, INSERT, UPDATE, DELETE ON shop.* TO 'web'@'localhost';
GRANT SELECT ON shop.* TO 'reporting'@'localhost';
SET PERSIST max_connections = 30;
SQL
db_stop
