export REDISCLI_AUTH=QB-Admin-2026
cp /backups/redis/quickbite-nightly.rdb /srv/redis/node2/dump.rdb
dbctl start node2
node2 --user admin --scan | while read -r k; do
  [ "$(node1 --user admin EXISTS "$k")" = 0 ] && node2 --user admin MIGRATE 127.0.0.1 6379 "$k" 0 5000 COPY AUTH2 admin QB-Admin-2026 >/dev/null
done
node1 --user admin CONFIG SET appendonly yes
node1 --user admin CONFIG SET appendfsync everysec
node1 --user admin CONFIG SET save '3600 1 300 100 60 10000'
node1 --user admin CONFIG REWRITE
dbctl stop node2
