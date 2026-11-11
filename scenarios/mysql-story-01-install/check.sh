#!/bin/bash
. /usr/local/lib/sad/lib.sh
M=/opt/sad/bin/mysql
pid=$(pgrep -x mysqld | head -1)
[ -n "$pid" ] || fail "no mysqld is running"
[ -x /opt/mysql/bin/mysqld ] || fail "/opt/mysql/bin/mysqld doesn't exist: unpack the tarball into /opt/mysql"
R="$M -h 127.0.0.1 -P 3306 -u root -plb-root-7Qx2-tarball -N -B"
out=$($R -e "select 1" 2>&1 | grep -v 'Using a password')
[ "$out" = 1 ] || fail "can't log in as root with the password from ~/README.md: $out"
read basedir datadir bind ver <<< "$($R -e "select @@basedir, @@datadir, @@bind_address, @@version" 2>/dev/null)"
[[ "$basedir" == /opt/mysql* ]] || fail "basedir is $basedir, expected /opt/mysql"
[ "${datadir%/}" = /srv/mysql/data ] || fail "datadir is $datadir, expected /srv/mysql/data"
[ "$bind" = 127.0.0.1 ] || fail "bind_address is $bind: listen on 127.0.0.1 only"
[ "$ver" = 8.4.13 ] || fail "server version is $ver, expected 8.4.13 from the tarball"
cfg=$(/opt/mysql/bin/my_print_defaults --defaults-file=/etc/my.cnf mysqld 2>/dev/null)
echo "$cfg" | grep -qE -- '--datadir=/srv/mysql/data/?$' || fail "/etc/my.cnf doesn't set datadir=/srv/mysql/data: a restart would come back wrong"
echo "$cfg" | grep -q -- '--bind-address=127.0.0.1' || fail "/etc/my.cnf doesn't set bind-address=127.0.0.1"
anon=$($R -e "select count(*) from mysql.user where user='' or (user='root' and host<>'localhost')" 2>/dev/null)
[ "$anon" = 0 ] || fail "there are anonymous or remote root accounts"
A="$M -h 127.0.0.1 -P 3306 -u bookstore_app -plb-app-9Fk3-orders -N -B bookstore"
out=$($A -e "create table sad_probe (id int primary key); drop table sad_probe; select 'ok'" 2>&1 | grep -v 'Using a password')
[ "$out" = ok ] || fail "bookstore_app can't log in and create tables in bookstore: $out"
g=$($R -e "show grants for 'bookstore_app'@'localhost'" 2>/dev/null | grep -v 'GRANT USAGE ON \*\.\*' | grep -vc 'ON `bookstore`\.\*')
[ "$g" = 0 ] || fail "bookstore_app has privileges beyond the bookstore database"
grep -q '/opt/mysql/bin' /home/player/.bashrc /home/player/.bash_profile 2>/dev/null || fail "add /opt/mysql/bin to PATH in ~/.bashrc"
pass "MySQL 8.4.13 from the tarball: configured in /etc/my.cnf, root secured, bookstore_app scoped to bookstore"
