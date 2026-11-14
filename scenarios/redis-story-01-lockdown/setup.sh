#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
node_conf 1 "save 3600 1 300 100 60 10000"
# Ravi's demo settings
sed -i 's/^bind .*/bind * -::*/; s/^protected-mode .*/protected-mode no/' /etc/redis/nodes/node1.conf
node_start 1
load_quickbite 6379
rn 1 SAVE >/dev/null
node_stop 1
cat > /home/player/README.md <<'MD'
# Lock down Redis (Maya)

  node1     127.0.0.1:6379 (and every other interface...), config /etc/redis/nodes/node1.conf
  admin     user admin / QB-Admin-2026     everything
  app       user app   / QB-App-2026       keys + channels qb:*, nothing @dangerous
  default   disabled
  network   localhost only, protected-mode yes
  must survive: sudo systemctl restart redis-server@node1
MD
chown redis:redis /home/player/README.md
