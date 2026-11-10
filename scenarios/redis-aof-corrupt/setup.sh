#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
sed -i 's/^appendonly no/appendonly yes/' /etc/redis/redis.conf
db_start
for i in $(seq 1 10000); do echo "SET key:$i value-$i"; done | redis-cli --pipe >/dev/null
redis-cli set last-write-before-crash "$(date)" >/dev/null
db_stop
f=$(ls /srv/redis/appendonlydir/*.incr.aof)
off=$(grep -a -b -o 'key:9950' "$f" | head -1 | cut -d: -f1)
off=$((off - 30))
{ head -c "$off" "$f"; printf '*3\r\n$3\r\nSET\r\n$7\r\nkey:\x00\x00\x00!!GARBAGE-AFTER-POWER-LOSS\r\n'; tail -c +$((off + 1)) "$f"; } > "$f.tmp"
mv "$f.tmp" "$f"; chown redis:redis "$f"
