#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
node_init 1
load_verdant 1
mq 1 "db.getSiblingDB('admin').createUser({ user: 'admin', pwd: 'Verdant-Admin-2026', roles: [{ role: 'root', db: 'admin' }] })" >/dev/null
mq 1 "db.getSiblingDB('verdant').createUser({ user: 'verdant_app', pwd: 'Verdant-App-2026', roles: [{ role: 'readWrite', db: 'verdant' }] })" >/dev/null
node_stop 1
printf 'security:\n  authorization: enabled\n' >> /etc/mongodb/nodes/node1.conf
node_conf 2; node_conf 3
echo "MONGO_URL='mongodb://verdant_app:Verdant-App-2026@127.0.0.1:27017,127.0.0.1:27018,127.0.0.1:27019/verdant?authSource=verdant&replicaSet=rs0'" > /srv/app/app.env
chown mongodb:mongodb /srv/app/app.env /etc/mongodb
cat > /home/player/README.md <<'MD'
# rs0 (Lena)

  node1   127.0.0.1:27017   standalone, access control on, all the data
  node2   127.0.0.1:27018   running, empty, standalone
  node3   127.0.0.1:27019   running, empty, standalone
  goal    replica set rs0, three data-bearing members, keyfile auth between them
  admin   admin / Verdant-Admin-2026 (authSource admin)
  app     /srv/app/app.env (replicaSet=rs0) -- leave it as it is
MD
chown mongodb:mongodb /home/player/README.md
