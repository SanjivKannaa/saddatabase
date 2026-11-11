cd /srv/mysql/node1
read f p <<< "$(zcat /backups/bookstore-nightly.sql.gz | grep -m1 'CHANGE REPLICATION SOURCE' | sed -E "s/.*SOURCE_LOG_FILE='([^']+)', SOURCE_LOG_POS=([0-9]+).*/\1 \2/")"
files=$(ls binlog.0* | awk -v f="$f" '$0 >= f')
dropfile=$(for b in $files; do mysqlbinlog "$b" | grep -qi 'drop table' && { echo $b; break; }; done)
stop=$(mysqlbinlog "$dropfile" | grep -i -B12 'DROP TABLE' | grep -o '^# at [0-9]*' | tail -1 | awk '{print $3}')
use=$(echo "$files" | awk -v d="$dropfile" '$0 <= d')
mysql -e 'CREATE DATABASE restore_scratch'
zcat /backups/bookstore-nightly.sql.gz | sed '/^CREATE DATABASE/d; s/^USE `bookstore`;/USE `restore_scratch`;/' | mysql
mysqlbinlog --rewrite-db='bookstore->restore_scratch' --database=restore_scratch --start-position=$p --stop-position=$stop $use | mysql
mysql -e 'RENAME TABLE restore_scratch.orders TO bookstore.orders; DROP DATABASE restore_scratch'
