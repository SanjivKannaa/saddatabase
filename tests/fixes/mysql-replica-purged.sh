node2 -e "STOP REPLICA; SET GLOBAL super_read_only = OFF; DROP DATABASE IF EXISTS bookstore; RESET BINARY LOGS AND GTIDS;"
mysqldump -S /var/run/mysqld/node1.sock --single-transaction --set-gtid-purged=ON --databases bookstore | node2
node2 -e "START REPLICA; SET PERSIST super_read_only = ON;"
sleep 3
