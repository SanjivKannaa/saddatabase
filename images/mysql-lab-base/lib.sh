# Helpers for story setup/start/check scripts (run as root).
# node_init N [extra cnf lines...]   create + initialise nodeN (port 3305+N), root pw lab-root-pw, grader account
# node_start N | node_stop N | node_kill N
# ns N  <<SQL ... SQL                admin SQL on nodeN (grader account, auth_socket)
# nq N "select ..."                  one value from nodeN
node_init() {
  local n=$1; shift
  sed "s/@N@/$n/g; s/@PORT@/$((3305 + n))/g" /usr/local/lib/sad/node.cnf.tmpl > /etc/mysql/nodes/node$n.cnf
  for l in "$@"; do echo "$l" >> /etc/mysql/nodes/node$n.cnf; done
  chown mysql:mysql /etc/mysql/nodes/node$n.cnf
  su mysql -c "mysqld --defaults-file=/etc/mysql/nodes/node$n.cnf --initialize-insecure" 2>/dev/null
  node_start $n
  mysql -S /var/run/mysqld/node$n.sock -uroot -e "INSTALL PLUGIN auth_socket SONAME 'auth_socket.so';
    CREATE USER sadgrader@localhost IDENTIFIED WITH auth_socket AS 'root'; GRANT ALL ON *.* TO sadgrader@localhost WITH GRANT OPTION;
    ALTER USER root@localhost IDENTIFIED BY 'lab-root-pw';"
  # each node starts with an empty binlog/GTID history, so replicas don't replay another node's bootstrap
  mysql -S /var/run/mysqld/node$n.sock -u sadgrader -e "RESET BINARY LOGS AND GTIDS"
}
node_start() { su mysql -c "/usr/local/lib/sad/svc start node$1" >/dev/null; }
node_stop()  { su mysql -c "/usr/local/lib/sad/svc stop node$1" >/dev/null; }
node_kill()  { local p=/var/run/mysqld/node$1.pid; [ -s $p ] && kill -9 "$(cat $p)" 2>/dev/null; rm -f $p /var/run/mysqld/node$1.sock /var/run/mysqld/node$1.sock.lock; }
ns() { local n=$1; shift; mysql -S /var/run/mysqld/node$n.sock -u sadgrader "$@"; }
nq() { mysql -S /var/run/mysqld/node$1.sock -u sadgrader -N -B ${3:+-D "$3"} -e "$2" 2>/dev/null; }
db_start() { for f in /etc/mysql/nodes/node?.cnf; do [ -f "$f" ] && node_start "$(basename "$f" .cnf | tr -dc 0-9)"; done; }
db_stop()  { for f in /etc/mysql/nodes/node?.cnf; do [ -f "$f" ] && node_stop "$(basename "$f" .cnf | tr -dc 0-9)"; done; }
# replication status field of nodeN: rs N Replica_SQL_Running
rs() { mysql -S /var/run/mysqld/node$1.sock -u sadgrader -e "SHOW REPLICA STATUS\G" 2>/dev/null | sed -n "s/^ *$2: //p"; }
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
