export REDISCLI_AUTH=QB-Admin-2026
node1 --user admin CONFIG SET masteruser replica
node1 --user admin CONFIG SET masterauth QB-Repl-2026
node1 --user admin CONFIG REWRITE
for i in 1 2 3; do
  mkdir -p /srv/redis/sentinel$i
  cat > /etc/redis/sentinel/sentinel$i.conf <<CONF
port $((26378 + i))
bind 127.0.0.1
daemonize yes
pidfile /var/run/redis/sentinel$i.pid
logfile /var/log/redis/sentinel$i.log
dir /srv/redis/sentinel$i
sentinel monitor quickbite 127.0.0.1 6379 2
sentinel auth-user quickbite sentinel
sentinel auth-pass quickbite QB-Sentinel-2026
sentinel down-after-milliseconds quickbite 5000
sentinel failover-timeout quickbite 30000
CONF
  dbctl start sentinel$i
done
sleep 6
