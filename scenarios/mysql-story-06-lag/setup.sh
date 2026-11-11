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
CREATE USER 'backup_agent'@'localhost' IDENTIFIED BY 'Backup-Lumen-2026';
GRANT SELECT, RELOAD, LOCK TABLES, PROCESS, SHOW VIEW, EVENT, TRIGGER, REPLICATION CLIENT ON *.* TO 'backup_agent'@'localhost';
CREATE DATABASE bookstore;
USE bookstore;
CREATE TABLE heartbeat (id INT PRIMARY KEY, ts DATETIME(6) NOT NULL);
INSERT INTO heartbeat VALUES (1, NOW(6));
CREATE TABLE orders (id INT AUTO_INCREMENT PRIMARY KEY, customer_id INT NOT NULL, total DECIMAL(10,2) NOT NULL, status VARCHAR(12) NOT NULL, created_at DATETIME NOT NULL);
SQL
gt=$(nq 1 "select @@gtid_executed" | tr -d '\n'); [ "$(nq 2 "select wait_for_executed_gtid_set('$gt', 30)")" = 0 ]
mkdir -p /srv/backup
cat > /srv/backup/nightly.sh <<'SH'
#!/bin/bash
# nightly logical backup of the replica (so we don't load the primary) -- set up by Marco, 2024
set -e
OUT=/srv/backup/dump-$(date +%F).sql.gz
mysqldump -S /var/run/mysqld/node2.sock -u backup_agent -pBackup-Lumen-2026 \
  --lock-all-tables --all-databases --routines --events --triggers | gzip > "$OUT"
find /srv/backup -name 'dump-*.sql.gz' -mtime +7 -delete
SH
chmod 755 /srv/backup/nightly.sh; chown -R mysql:mysql /srv/backup
node_stop 1; node_stop 2
rm -f /usr/local/bin/node3
