export REDISCLI_AUTH=QB-Admin-2026
for n in 4 5 6 7 8 9; do
  cat >> /etc/redis/nodes/node$n.conf <<CONF
cluster-enabled yes
cluster-config-file nodes-node$n.conf
cluster-node-timeout 5000
masteruser replica
masterauth QB-Repl-2026
CONF
  dbctl restart node$n
done
redis-cli --user admin --cluster create 127.0.0.1:7001 127.0.0.1:7002 127.0.0.1:7003 \
  127.0.0.1:7004 127.0.0.1:7005 127.0.0.1:7006 --cluster-replicas 1 --cluster-yes
until redis-cli --user admin -p 7001 CLUSTER INFO | grep -q 'cluster_state:ok'; do sleep 1; done
redis-cli --user admin --cluster import 127.0.0.1:7001 --cluster-from 127.0.0.1:6379 \
  --cluster-from-user admin --cluster-from-pass QB-Admin-2026 --cluster-copy
sleep 3
