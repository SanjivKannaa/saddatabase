node1 -e "CREATE USER 'repl'@'127.0.0.1' IDENTIFIED BY 'Repl-Lumen-2026'; GRANT REPLICATION SLAVE ON *.* TO 'repl'@'127.0.0.1';"
sed -i 's/^server_id .*/server_id = 2/; /^gtid_mode/d; /^enforce_gtid_consistency/d' /etc/mysql/nodes/node2.cnf
printf 'gtid_mode = ON\nenforce_gtid_consistency = ON\n' >> /etc/mysql/nodes/node2.cnf
dbctl restart node2
node2 -e "RESET BINARY LOGS AND GTIDS"
mysqldump -S /var/run/mysqld/node1.sock --single-transaction --set-gtid-purged=ON --databases bookstore | node2
node2 -e "CHANGE REPLICATION SOURCE TO SOURCE_HOST='127.0.0.1', SOURCE_PORT=3306, SOURCE_USER='repl', SOURCE_PASSWORD='Repl-Lumen-2026', SOURCE_AUTO_POSITION=1, GET_SOURCE_PUBLIC_KEY=1; START REPLICA; SET PERSIST super_read_only = ON;"
sleep 3
