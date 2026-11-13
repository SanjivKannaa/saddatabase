#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
node_init 1 "appendonly yes" "appendfsync everysec" "enable-debug-command local"
redis-cli -p 6379 ACL SETUSER admin on '>QB-Admin-2026' '~*' '&*' '+@all' >/dev/null
redis-cli -p 6379 ACL SETUSER app on '>QB-App-2026' '~qb:*' '&qb:*' '+@all' '-@dangerous' >/dev/null
redis-cli -p 6379 ACL SETUSER replica on '>QB-Repl-2026' '+psync' '+replconf' '+ping' >/dev/null
redis-cli -p 6379 ACL SETUSER default off >/dev/null
export SAD_USER=admin SAD_PASS=QB-Admin-2026
rn 1 CONFIG REWRITE >/dev/null
load_quickbite 6379
for i in $(seq 60); do rn 1 INFO persistence | grep -q '^aof_rewrite_in_progress:0' && break; sleep 0.5; done
rn 1 DBSIZE > /opt/sad/dbsize
# the six new instances: plain standalone Redis, same users
for n in 4 5 6 7 8 9; do
  PORT=$((6997 + n)) node_conf $n "appendonly yes" "enable-debug-command local"
  grep '^user ' /etc/redis/nodes/node1.conf >> /etc/redis/nodes/node$n.conf
done
node_stop 1
cat > /home/player/README.md <<'MD'
# Redis Cluster migration (Maya)

  node1          127.0.0.1:6379        standalone, all the data. Leave it as it is (rollback plan).
  node4..node9   127.0.0.1:7001-7006   new instances, empty, standalone. configs /etc/redis/nodes/node4..9.conf
  target         one cluster, 3 masters + 3 replicas, every key from node1 (TTLs too)

  users (all nodes)   admin / QB-Admin-2026    app / QB-App-2026    replica / QB-Repl-2026
  tip                 export REDISCLI_AUTH=QB-Admin-2026; redis-cli --user admin -c -p 7001 ...
MD
chown redis:redis /home/player/README.md
