#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
node_init 1
ns 1 <<'SQL'
CREATE DATABASE bookstore;
USE bookstore;
CREATE TABLE customers (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(80), email VARCHAR(120), loyalty_points INT NOT NULL DEFAULT 0);
CREATE TABLE orders (id INT AUTO_INCREMENT PRIMARY KEY, customer_id INT NOT NULL, total DECIMAL(10,2) NOT NULL, status VARCHAR(12) NOT NULL, created_at DATETIME NOT NULL, KEY (customer_id));
SET SESSION cte_max_recursion_depth = 10000;
INSERT INTO customers (name, email, loyalty_points) WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 500) SELECT CONCAT('Reader ', i), CONCAT('reader', i, '@mail.test'), FLOOR(RAND()*100) FROM n;
INSERT INTO orders (customer_id, total, status, created_at) WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 3000) SELECT 1 + FLOOR(RAND()*500), ROUND(5 + RAND()*80, 2), 'shipped', NOW() - INTERVAL FLOOR(RAND()*400) DAY FROM n;
SQL
# the nightly backup (02:00)
mkdir -p /backups
mysqldump -S /var/run/mysqld/node1.sock -u sadgrader --single-transaction --source-data=2 --flush-logs --databases bookstore | gzip > /backups/bookstore-nightly.sql.gz
# today's traffic: new orders, order updates, customer changes, a log rotation
for b in 1 2 3; do
  ns 1 bookstore <<'SQL'
INSERT INTO orders (customer_id, total, status, created_at) SELECT 1 + FLOOR(RAND()*500), ROUND(5 + RAND()*80, 2), 'paid', NOW() FROM customers LIMIT 70;
UPDATE orders SET status = 'shipped' WHERE status = 'paid' AND id % 3 = 0;
UPDATE customers SET loyalty_points = loyalty_points + 5 WHERE id % 7 = 0;
SQL
  ns 1 -e "FLUSH BINARY LOGS"
done
ns 1 bookstore -e "INSERT INTO orders (customer_id, total, status, created_at) VALUES (42, 129.99, 'paid', NOW()), (7, 18.50, 'paid', NOW())"
# what "right before the drop" looks like (root-only)
nq 1 "CHECKSUM TABLE bookstore.orders" | awk '{print $2}' > /opt/sad/orders.checksum
nq 1 "SELECT COUNT(*) FROM bookstore.orders" > /opt/sad/orders.count
# 14:02 -- the accident, then life goes on for customers
ns 1 bookstore -e "DROP TABLE orders"
ns 1 bookstore <<'SQL'
UPDATE customers SET loyalty_points = loyalty_points + 50 WHERE id <= 40;
INSERT INTO customers (name, email) VALUES ('Late Reader', 'late@mail.test'), ('Night Owl', 'owl@mail.test');
SQL
nq 1 "CHECKSUM TABLE bookstore.customers" | awk '{print $2}' > /opt/sad/customers.checksum
node_stop 1
chmod 644 /backups/bookstore-nightly.sql.gz
rm -f /usr/local/bin/node2 /usr/local/bin/node3
cat > /home/player/README.md <<'MD'
# Incident: bookstore.orders dropped (prod)

  server        node1  (127.0.0.1:3306), `mysql` = root
  backup        /backups/bookstore-nightly.sql.gz   (mysqldump --single-transaction --source-data=2, 02:00)
  binlogs       /srv/mysql/node1/binlog.*            (format ROW)
  tools         mysql, mysqldump, mysqlbinlog

  Goal: orders back exactly as before the DROP. customers must keep today's changes.
MD
chown mysql:mysql /home/player/README.md
