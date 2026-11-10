# Helpers for scenario setup/start/check scripts (run as root).
db_start() { su mongodb -c "dbctl start" >/dev/null; }
db_stop()  { su mongodb -c "dbctl stop" >/dev/null; }
MONGO_URI=${MONGO_URI:-mongodb://127.0.0.1:27017}
# js: run a script (stdin or arg) in mongosh. q 'expr' [db] prints one value.
js() { if [ $# -gt 0 ]; then mongosh --quiet "$MONGO_URI/${2:-test}" --eval "$1"; else local f; f=$(mktemp --suffix .js); cat > "$f"; mongosh --quiet "$MONGO_URI/test" --file "$f"; local rc=$?; rm -f "$f"; return $rc; fi; }
q()  { mongosh --quiet "$MONGO_URI/${2:-test}${MONGO_OPTS:-}" --eval "$1" 2>/dev/null | tail -1; }
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
