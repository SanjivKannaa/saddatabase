# Helpers for scenario setup/start/check scripts (run as root).
db_start() { su redis -c "dbctl start" >/dev/null; }
db_stop()  { su redis -c "dbctl stop" >/dev/null; }
r() { redis-cli "$@"; }
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
