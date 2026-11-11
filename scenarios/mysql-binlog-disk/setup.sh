#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
node_init 1 "gtid_mode = ON" "enforce_gtid_consistency = ON" "binlog_expire_logs_seconds = 0" "max_binlog_size = 1M"
node_init 2 "gtid_mode = ON" "enforce_gtid_consistency = ON" "skip_replica_start = ON   # paused for maintenance: replication stays stopped across restarts"
ns 1 -e "CREATE USER 'repl'@'127.0.0.1' IDENTIFIED BY 'Repl-Lumen-2026'; GRANT REPLICATION SLAVE ON *.* TO 'repl'@'127.0.0.1';
         CREATE DATABASE shop; CREATE TABLE shop.events (id INT AUTO_INCREMENT PRIMARY KEY, payload VARCHAR(200), at DATETIME);"
ns 2 -e "CHANGE REPLICATION SOURCE TO SOURCE_HOST='127.0.0.1', SOURCE_PORT=3306, SOURCE_USER='repl', SOURCE_PASSWORD='Repl-Lumen-2026', SOURCE_AUTO_POSITION=1, GET_SOURCE_PUBLIC_KEY=1, SOURCE_CONNECT_RETRY=2; START REPLICA; SET PERSIST super_read_only = ON;"
churn() { for b in $(seq 1 "$1"); do ns 1 shop -e "SET SESSION cte_max_recursion_depth=5000; INSERT INTO events (payload, at) WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 4000) SELECT REPEAT('x', 180), NOW() FROM n; DELETE FROM events WHERE id % 2 = 0;"; done; }
churn 15
gt=$(nq 1 "select @@gtid_executed" | tr -d '\n'); [ "$(nq 2 "select wait_for_executed_gtid_set('$gt', 120)")" = 0 ]
ns 2 -e "STOP REPLICA"      # paused for maintenance
churn 15
node_stop 2; node_stop 1
