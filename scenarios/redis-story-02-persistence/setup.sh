#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
# node1: locked down last chapter, persistence switched off "for speed"
node_init 1 "enable-debug-command local"
redis-cli -p 6379 ACL SETUSER admin on '>QB-Admin-2026' '~*' '&*' '+@all' >/dev/null
redis-cli -p 6379 ACL SETUSER app on '>QB-App-2026' '~qb:*' '&qb:*' '+@all' '-@dangerous' >/dev/null
redis-cli -p 6379 ACL SETUSER default off >/dev/null
export SAD_USER=admin SAD_PASS=QB-Admin-2026
rn 1 CONFIG REWRITE >/dev/null
# the spare: same users, port 6380, stopped
PORT=6380 node_conf 2
grep '^user ' /etc/redis/nodes/node1.conf >> /etc/redis/nodes/node2.conf
# yesterday's data and Jo's nightly backup
load_quickbite 6379
mkdir -p /backups/redis
rp 6379 --rdb /backups/redis/quickbite-nightly.rdb >/dev/null 2>&1
chown -R redis:redis /backups/redis; chmod 644 /backups/redis/quickbite-nightly.rdb
for i in $(seq 60); do rn 1 INFO persistence | grep -q '^rdb_bgsave_in_progress:0' && break; sleep 0.5; done
# the reboot: everything gone. Then the morning: new logins, refilled carts, a new order queue, new users.
rn 1 FLUSHALL >/dev/null
awk 'BEGIN {
  for (i = 1; i <= 300; i++) { printf "HSET qb:session:m%07d user %d status active device android\n", i, 1+(i*11)%2000; printf "EXPIRE qb:session:m%07d 604800\n", i }
  for (i = 1; i <= 100; i++) printf "HSET qb:cart:%d item:%d 1 note morning-%d\n", i, 299-i, i
  for (o = 1; o <= 40; o++) printf "RPUSH qb:orders:pending order-m%04d\n", o
  for (i = 2001; i <= 2050; i++) printf "HSET qb:user:%d name Customer-%d city Coimbra plan free\n", i, i
}' | rn 1 --pipe >/dev/null
[ "$(rn 1 SAVE)" = OK ]; cp /srv/redis/node1/dump.rdb /opt/sad/morning.rdb
# what the merged dataset must look like: compute it once (reference merge), remember per-key digests
cp /backups/redis/quickbite-nightly.rdb /srv/redis/node2/dump.rdb; chown redis:redis /srv/redis/node2/dump.rdb
node_start 2
rn 2 --scan | while read -r k; do
  [ "$(rn 1 EXISTS "$k")" = 0 ] && rn 2 MIGRATE 127.0.0.1 6379 "$k" 0 5000 COPY AUTH2 admin QB-Admin-2026 >/dev/null
done
rn 1 --scan | sort > /opt/sad/keys
xargs -a /opt/sad/keys redis-cli -p 6379 --user admin --pass QB-Admin-2026 --no-auth-warning DEBUG DIGEST-VALUE | paste -d' ' /opt/sad/keys - > /opt/sad/expected.digest
node_stop 2; rm -f /srv/redis/node2/dump.rdb
# back to the morning state for the player (node1 loads dump.rdb on start; nothing else persists)
node_stop 1; cp /opt/sad/morning.rdb /srv/redis/node1/dump.rdb; chown redis:redis /srv/redis/node1/dump.rdb
cat > /home/player/README.md <<'MD'
# Incident: Redis came back empty after the reboot (Jo)

  node1    127.0.0.1:6379   production, morning data only. config /etc/redis/nodes/node1.conf
  node2    127.0.0.1:6380   spare, stopped, empty (dir /srv/redis/node2)
  backup   /backups/redis/quickbite-nightly.rdb   (last night, redis-cli --rdb)
  login    export REDISCLI_AUTH=QB-Admin-2026; node1 --user admin ...

  Restore what's missing. Today's keys win. Then: crash-proof.
MD
chown redis:redis /home/player/README.md
