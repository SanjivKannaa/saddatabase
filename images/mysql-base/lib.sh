# Helpers for scenario setup/start/check scripts (run as root).
db_start() { su mysql -c "dbctl start" >/dev/null; }
db_stop()  { su mysql -c "dbctl stop" >/dev/null; }
# admin SQL over the socket as the grader account (auth_socket, OS root). sql <<EOF ... ; q "select ..." [db]
sql() { mysql -u sadgrader "$@"; }
q()   { mysql -u sadgrader -N -B ${2:+-D "$2"} -e "$1" 2>/dev/null; }
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
