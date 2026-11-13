#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
users() {
  redis-cli -p "$1" ACL SETUSER admin on '>QB-Admin-2026' '~*' '&*' '+@all' >/dev/null
  redis-cli -p "$1" ACL SETUSER app on '>QB-App-2026' '~qb:*' '&qb:*' '+@all' '-@dangerous' >/dev/null
  redis-cli -p "$1" ACL SETUSER default off >/dev/null
}
node_init 1 "appendonly yes" "appendfsync everysec" "save 3600 1 300 100 60 10000"
users 6379
export SAD_USER=admin SAD_PASS=QB-Admin-2026
load_quickbite 6379
# Ravi, last night: "safety" from a blog post
rn 1 CONFIG SET min-replicas-to-write 1 >/dev/null; rn 1 CONFIG SET min-replicas-max-lag 10 >/dev/null
rn 1 CONFIG REWRITE >/dev/null
# node2: provisioned, empty, Ravi's test settings
node_init 2 "replica-read-only no"
SAD_USER= SAD_PASS= users 6380
rn 2 CONFIG REWRITE >/dev/null
for i in $(seq 60); do rn 1 INFO persistence | grep -q '^aof_rewrite_in_progress:0' && break; sleep 0.5; done
node_stop 2; node_stop 1
cat > /home/player/README.md <<'MD'
# NOREPLICAS (Jo, 08:05)

  node1    primary  127.0.0.1:6379   min-replicas-to-write 1 (keep it)
  node2    spare    127.0.0.1:6380   running, empty: make it node1's replica
  login    export REDISCLI_AUTH=QB-Admin-2026; node1 --user admin ...
  configs  /etc/redis/nodes/node1.conf, node2.conf
MD
chown redis:redis /home/player/README.md
