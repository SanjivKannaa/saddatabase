#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
node_init 1 "appendonly yes" "appendfsync everysec" "latency-monitor-threshold 5"
redis-cli -p 6379 ACL SETUSER admin on '>QB-Admin-2026' '~*' '&*' '+@all' >/dev/null
redis-cli -p 6379 ACL SETUSER app on '>QB-App-2026' '~qb:*' '&qb:*' '+@all' '-@dangerous' >/dev/null
redis-cli -p 6379 ACL SETUSER default off >/dev/null
export SAD_USER=admin SAD_PASS=QB-Admin-2026
rn 1 CONFIG REWRITE >/dev/null
load_quickbite 6379
# rate-limit counters: lots of small keys
awk 'BEGIN { for (i = 1; i <= 150000; i++) printf "SET qb:ratelimit:10.%d.%d.%d 1 EX 2592000\n", int(i/65536), int(i/256)%256, i%256 }' | rn 1 --pipe >/dev/null
for i in $(seq 60); do rn 1 INFO persistence | grep -q '^aof_rewrite_in_progress:0' && break; sleep 0.5; done
node_stop 1
cat > /srv/app/session-cleaner.sh <<'SH'
#!/bin/bash
# Removes logged-out sessions (status = closed). Runs every 2 seconds.
# Ravi: uses admin because the app user isn't allowed to run KEYS.
export REDISCLI_AUTH=QB-Admin-2026
rc() { redis-cli -p 6379 --user admin --no-auth-warning "$@"; }
keys=$(rc KEYS 'qb:session:*')
[ -z "$keys" ] && exit 0
statuses=$(for k in $keys; do echo "HGET $k status"; done | rc)
paste <(echo "$keys") <(echo "$statuses") | awk '$2 == "closed" { print "DEL " $1 }' | rc >/dev/null
SH
cat > /srv/app/menu-refresh.sh <<'SH'
#!/bin/bash
# Rebuilds the combined menu (qb:menu:all, ~250k dishes) from the restaurants' feeds. Runs every 15 seconds.
export REDISCLI_AUTH=QB-Admin-2026
rc() { redis-cli -p 6379 --user admin --no-auth-warning "$@"; }
rc DEL qb:menu:all >/dev/null
awk -v t=$(date +%s) 'BEGIN { for (b = 0; b < 250; b++) { printf "HSET qb:menu:all"; for (i = 0; i < 1000; i++) printf " dish:%d price-%d-eur", b*1000+i, (i*7+t)%40; print "" } }' | rc --pipe >/dev/null
rc HSET qb:menu:all _built "$(date +%s)" >/dev/null
SH
chown redis:redis /srv/app/*.sh; chmod 755 /srv/app/*.sh
cat > /home/player/README.md <<'MD'
# Latency comb (Jo)

  node1          127.0.0.1:6379     login: export REDISCLI_AUTH=QB-Admin-2026; node1 --user admin ...
  jobs           /srv/app/session-cleaner.sh   every 2 s
                 /srv/app/menu-refresh.sh      every 15 s
  symptoms       a stall every 2 s, a bigger one every 15 s
MD
chown redis:redis /home/player/README.md
