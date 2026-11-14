# Helpers for Redis story setup/start/check scripts (run as root).
# node_init N [extra config lines...]   write /etc/redis/nodes/nodeN.conf (port 6378+N) and start it
# node_start N | node_stop N | node_kill N
# rn N args...      redis-cli on nodeN; authenticates as $SAD_USER/$SAD_PASS when set
# rp PORT args...   same, by port
nport() { echo $((6378 + $1)); }
node_conf() {
  local n=$1 p=${PORT:-$((6378 + $1))}; shift
  mkdir -p /srv/redis/node$n
  { cat <<CONF
# node$n
port $p
bind 127.0.0.1
protected-mode yes
daemonize yes
pidfile /var/run/redis/node$n.pid
logfile /var/log/redis/node$n.log
dir /srv/redis/node$n
dbfilename dump.rdb
appendonly no
save ""
CONF
    for l in "$@"; do echo "$l"; done; } > /etc/redis/nodes/node$n.conf
  chown -R redis:redis /etc/redis/nodes/node$n.conf /srv/redis/node$n
}
node_init()  { node_conf "$@"; node_start "$1"; }
node_start() { runuser -u redis -- /usr/local/lib/sad/svc start node$1 >/dev/null; }
node_stop()  { runuser -u redis -- /usr/local/lib/sad/svc stop node$1 >/dev/null; }
node_kill()  { local p=/var/run/redis/node$1.pid; [ -s $p ] && kill -9 "$(cat $p)" 2>/dev/null; sleep 0.3; rm -f $p; }
rp() { local p=$1; shift; redis-cli -p "$p" ${SAD_USER:+--user "$SAD_USER"} ${SAD_PASS:+--pass "$SAD_PASS"} --no-auth-warning "$@"; }
rn() { local n=$1; shift; rp "$(nport $n)" "$@"; }
db_start() { for f in /etc/redis/nodes/node*.conf /etc/redis/sentinel/sentinel*.conf; do [ -f "$f" ] && runuser -u redis -- /usr/local/lib/sad/svc start "$(basename "$f" .conf)" >/dev/null; done; }
db_stop()  { for f in /etc/redis/sentinel/sentinel*.conf /etc/redis/nodes/node*.conf; do [ -f "$f" ] && runuser -u redis -- /usr/local/lib/sad/svc stop "$(basename "$f" .conf)" >/dev/null; done; }
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
# load_quickbite PORT : Quickbite's keys. users 2000 (hash), sessions 3000 (hash, 7-day TTL), carts 1500 (hash),
# menus 200 (JSON string), qb:orders:pending (list of 500). Deterministic except session ids.
load_quickbite() {
  awk 'BEGIN {
    srand(42); city[0]="Lisbon"; city[1]="Porto"; city[2]="Braga"; city[3]="Faro"
    for (i = 1; i <= 2000; i++) printf "HSET qb:user:%d name Customer-%d city %s plan %s\n", i, i, city[i%4], (i%9==0 ? "plus" : "free")
    for (i = 1; i <= 3000; i++) { printf "HSET qb:session:%08x user %d status active device %s\n", i*2654435761%4294967296, 1+(i*7)%2000, (i%3 ? "android" : "ios"); printf "EXPIRE qb:session:%08x %d\n", i*2654435761%4294967296, 604800 - i }
    for (i = 1; i <= 1500; i++) printf "HSET qb:cart:%d item:%d %d item:%d %d\n", i, i%300, 1+i%3, (i*7)%300, 1+i%2
    for (r = 1; r <= 200; r++) printf "SET qb:menu:%d \047{\"restaurant\":%d,\"items\":%d,\"open\":%s}\047\n", r, r, 20+r%30, (r%5 ? "true" : "false")
    for (o = 1; o <= 500; o++) printf "RPUSH qb:orders:pending order-%06d\n", o
  }' | rp "$1" --pipe >/dev/null
}
