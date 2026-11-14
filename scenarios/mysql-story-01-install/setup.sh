#!/bin/bash
set -euo pipefail
# No system MySQL in this box: keep a private client for the grader, then remove the packaged binaries.
mkdir -p /opt/sad/bin && cp /usr/bin/mysql /opt/sad/bin/mysql
rm -f /usr/sbin/mysqld /usr/bin/mysql /usr/bin/mysqladmin /usr/bin/mysqldump /usr/bin/mysqlbinlog /usr/bin/mysqlsh \
      /usr/bin/mysql_* /usr/bin/mysqlcheck /usr/bin/mysqlimport /usr/bin/mysqlshow /usr/bin/mysqlslap /usr/bin/my_print_defaults \
      /usr/local/bin/mysqlbinlog /usr/local/bin/node1 /usr/local/bin/node2 /usr/local/bin/node3 /usr/local/bin/systemctl /usr/local/bin/journalctl /usr/local/bin/service /usr/local/bin/sudo /home/player/.my.cnf
mkdir -p /opt/mysql /srv/mysql /home/player/downloads
touch /etc/my.cnf
chown mysql:mysql /opt/mysql /srv/mysql /etc/my.cnf /home/player/downloads
ln -s /opt/vendor/mysql-8.4.13-linux-glibc2.28-x86_64-minimal.tar.xz /home/player/downloads/
cat > /home/player/README.md <<'MD'
# db-01.lumenbooks (new) -- handoff from Priya

The old database was Marco's laptop MySQL copied to a VM. This one we do properly.

  MySQL      8.4.13, official tarball: ~/downloads/
  basedir    /opt/mysql
  datadir    /srv/mysql/data
  config     /etc/my.cnf
  listen     127.0.0.1:3306 only (the app runs on this box)

  root password            lb-root-7Qx2-tarball
  app database             bookstore
  app user                 'bookstore_app'@'localhost'
  app user password        lb-app-9Fk3-orders   (Marco's config already uses this)

Ping me when bookstore_app can log in and create tables in bookstore.
MD
cat > /etc/motd <<'MOTD'

 sadDatabase · Lumen Books · db-01 (empty)
 ─────────────────────────────────────────
 you     mysql (OS user, no sudo)
 start   cat ~/README.md
 owned   /opt/mysql /srv/mysql /etc/my.cnf
         /var/log/mysql /var/run/mysqld
MOTD
chown mysql:mysql /home/player/README.md
