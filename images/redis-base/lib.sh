# Helpers for scenario setup/start/check scripts (run as root).
db_start() { su redis -c "/usr/local/lib/sad/svc start" >/dev/null; }
db_stop()  { su redis -c "/usr/local/lib/sad/svc stop" >/dev/null; }
r() { redis-cli "$@"; }
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
