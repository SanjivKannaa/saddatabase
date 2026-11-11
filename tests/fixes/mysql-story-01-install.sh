tar -xJf ~/downloads/mysql-8.4.13-linux-glibc2.28-x86_64-minimal.tar.xz -C /opt/mysql --strip-components=1
echo 'export PATH=/opt/mysql/bin:$PATH' >> ~/.bashrc; export PATH=/opt/mysql/bin:$PATH
cat > /etc/my.cnf <<'CNF'
[mysqld]
basedir      = /opt/mysql
datadir      = /srv/mysql/data
port         = 3306
socket       = /var/run/mysqld/mysqld.sock
bind-address = 127.0.0.1
log-error    = /var/log/mysql/error.log
[client]
socket       = /var/run/mysqld/mysqld.sock
CNF
mysqld --defaults-file=/etc/my.cnf --initialize
tmp=$(grep 'temporary password' /var/log/mysql/error.log | awk '{print $NF}')
mysqld --defaults-file=/etc/my.cnf --daemonize
for i in $(seq 30); do [ -S /var/run/mysqld/mysqld.sock ] && break; sleep 1; done
mysql -uroot -p"$tmp" --connect-expired-password -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'lb-root-7Qx2-tarball'"
mysql -uroot -plb-root-7Qx2-tarball -e "CREATE DATABASE bookstore; CREATE USER 'bookstore_app'@'localhost' IDENTIFIED BY 'lb-app-9Fk3-orders'; GRANT ALL ON bookstore.* TO 'bookstore_app'@'localhost';"
