# Helpers for MongoDB story setup/start/check scripts (run as root).
# node_conf N [extra YAML...]   write /etc/mongodb/nodes/nodeN.conf (port 27016+N); extra args are appended as
#                               top-level YAML (e.g. "replication:\n  replSetName: rs0")
# node_init N [extra YAML...]   node_conf + start
# node_start N | node_stop N | node_kill N
# mq N 'js expression'          run it in mongosh on nodeN (db admin), authenticated as $SAD_USER/$SAD_PASS when set
# mjs N < script.js             same with a script on stdin
nport() { echo $((27016 + $1)); }
node_conf() {
  local n=$1; shift
  mkdir -p /srv/mongo/node$n
  { cat <<CONF
# node$n
storage:
  dbPath: /srv/mongo/node$n
  wiredTiger:
    engineConfig:
      cacheSizeGB: 0.25
systemLog:
  destination: file
  path: /var/log/mongodb/node$n.log
  logAppend: true
net:
  port: $(nport $n)
  bindIp: 127.0.0.1
processManagement:
  fork: true
  pidFilePath: /var/run/mongodb/node$n.pid
CONF
    for l in "$@"; do printf '%b\n' "$l"; done; } > /etc/mongodb/nodes/node$n.conf
  chown -R mongodb:mongodb /etc/mongodb/nodes/node$n.conf /srv/mongo/node$n
}
node_init()  { node_conf "$@"; node_start "$1"; }
node_start() { runuser -u mongodb -- dbctl start node$1 >/dev/null; }
node_stop()  { runuser -u mongodb -- dbctl stop node$1 >/dev/null; }
node_kill()  { local p=/var/run/mongodb/node$1.pid; [ -s $p ] && kill -9 "$(cat $p)" 2>/dev/null; sleep 0.5; rm -f $p; }
muri() { local a=""; [ -n "${SAD_USER:-}" ] && a="$SAD_USER:$SAD_PASS@"; echo "mongodb://${a}127.0.0.1:$(nport $1)/${2:-admin}?directConnection=true${SAD_USER:+&authSource=admin}"; }
mq()  { mongosh --quiet "$(muri $1 ${3:-})" --eval "$2" 2>/dev/null | tail -1; }
mjs() { local f; f=$(mktemp --suffix .js); cat > "$f"; mongosh --quiet "$(muri $1 ${2:-})" --file "$f"; local rc=$?; rm -f "$f"; return $rc; }
db_start() { for f in /etc/mongodb/nodes/node?.conf; do [ -f "$f" ] && runuser -u mongodb -- dbctl start "$(basename "$f" .conf)" >/dev/null; done; }
db_stop()  { for f in /etc/mongodb/nodes/node?.conf; do [ -f "$f" ] && runuser -u mongodb -- dbctl stop "$(basename "$f" .conf)" >/dev/null; done; }
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
# load_verdant N : Verdant's database on nodeN (see verdant.js)
load_verdant() { mjs $1 verdant < /usr/local/lib/sad/verdant.js >/dev/null; }
