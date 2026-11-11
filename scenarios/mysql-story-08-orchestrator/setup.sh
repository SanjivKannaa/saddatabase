#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
for n in 1 2 3; do node_init $n "gtid_mode = ON" "enforce_gtid_consistency = ON"; done
ns 1 <<'SQL'
CREATE USER 'repl'@'127.0.0.1' IDENTIFIED BY 'Repl-Lumen-2026';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'127.0.0.1';
CREATE USER 'app'@'127.0.0.1' IDENTIFIED BY 'App-Lumen-2026';
SQL
for n in 2 3; do ns $n -e "CHANGE REPLICATION SOURCE TO SOURCE_HOST='127.0.0.1', SOURCE_PORT=3306, SOURCE_USER='repl', SOURCE_PASSWORD='Repl-Lumen-2026', SOURCE_AUTO_POSITION=1, GET_SOURCE_PUBLIC_KEY=1, SOURCE_CONNECT_RETRY=1; START REPLICA; SET PERSIST super_read_only = ON;"; done
ns 1 <<'SQL'
CREATE DATABASE bookstore;
USE bookstore;
CREATE TABLE orders (id INT AUTO_INCREMENT PRIMARY KEY, customer_id INT NOT NULL, total DECIMAL(10,2) NOT NULL, status VARCHAR(12) NOT NULL, created_at DATETIME NOT NULL);
GRANT SELECT, INSERT, UPDATE, DELETE ON bookstore.* TO 'app'@'127.0.0.1';
SQL
gt=$(nq 1 "select @@gtid_executed" | tr -d '\n'); for n in 2 3; do [ "$(nq $n "select wait_for_executed_gtid_set('$gt', 60)")" = 0 ]; done
node_stop 3; node_stop 2; node_stop 1
mkdir -p /srv/orchestrator
cp /usr/local/orchestrator/orchestrator-sample-sqlite.conf.json /srv/orchestrator/orchestrator-sample.conf.json
printf '# bookstore app database connection\nDB_HOST=127.0.0.1\nDB_PORT=3306\nDB_USER=app\nDB_NAME=bookstore\n' > /srv/app/db.env
chown -R mysql:mysql /srv/orchestrator /srv/app
echo 'export ORCHESTRATOR_API=http://127.0.0.1:3000/api' >> /home/player/.bashrc
