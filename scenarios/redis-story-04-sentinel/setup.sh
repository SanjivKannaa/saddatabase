#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
users() {
  local p=$1
  redis-cli -p $p ACL SETUSER admin on '>QB-Admin-2026' '~*' '&*' '+@all' >/dev/null
  redis-cli -p $p ACL SETUSER app on '>QB-App-2026' '~qb:*' '&qb:*' '+@all' '-@dangerous' >/dev/null
  redis-cli -p $p ACL SETUSER replica on '>QB-Repl-2026' '+psync' '+replconf' '+ping' >/dev/null
  redis-cli -p $p ACL SETUSER sentinel on '>QB-Sentinel-2026' allchannels '+multi' '+slaveof' '+ping' '+exec' '+subscribe' \
    '+config|rewrite' '+role' '+publish' '+info' '+client|setname' '+client|kill' '+script|kill' >/dev/null
  redis-cli -p $p ACL SETUSER default off >/dev/null
  redis-cli -p $p --user admin --pass QB-Admin-2026 --no-auth-warning CONFIG REWRITE >/dev/null
}
node_init 1 "appendonly yes" "appendfsync everysec"
users 6379
export SAD_USER=admin SAD_PASS=QB-Admin-2026
load_quickbite 6379
for n in 2 3; do
  node_init $n "appendonly yes" "appendfsync everysec" "masteruser replica" "masterauth QB-Repl-2026" "replicaof 127.0.0.1 6379"
  SAD_USER= SAD_PASS= users $(nport $n)
done
for i in $(seq 60); do [ "$(rn 1 INFO replication | tr -d '\r' | sed -n 's/^connected_slaves://p')" = 2 ] && break; sleep 0.5; done
for i in $(seq 60); do rn 1 INFO persistence | grep -q '^aof_rewrite_in_progress:0' && break; sleep 0.5; done
sleep 1
node_stop 3; node_stop 2; node_stop 1
cat > /home/player/README.md <<'MD'
# Sentinel for quickbite (Maya)

  node1   primary   127.0.0.1:6379
  node2   replica   127.0.0.1:6380
  node3   replica   127.0.0.1:6381
  sentinels         127.0.0.1:26379, 26380, 26381   (to do: /etc/redis/sentinel/sentinelN.conf, dbctl start sentinelN)
  master name       quickbite, quorum 2, notice a dead primary within 5 s

  ACL users on every node
    admin / QB-Admin-2026          everything
    replica / QB-Repl-2026         replication (node2 and node3 use it)
    sentinel / QB-Sentinel-2026    what Sentinel needs

  The app asks the Sentinels: SENTINEL get-master-addr-by-name quickbite (falls back to node1 if none answers)
MD
chown redis:redis /home/player/README.md
