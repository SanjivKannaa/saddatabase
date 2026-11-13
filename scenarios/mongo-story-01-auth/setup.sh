#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
node_conf 1
sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongodb/nodes/node1.conf
node_start 1
load_verdant 1
mq 1 "db.getSiblingDB('billing').invoices.insertMany(Array.from({length: 200}, (_, i) => ({ customer: 'grower' + (i % 12), amount: 1000 + i * 13, paid: i % 3 > 0 })))" >/dev/null
node_stop 1
echo "MONGO_URL='mongodb://verdant_app:Verdant-App-2026@127.0.0.1:27017/verdant?authSource=verdant'" > /srv/app/app.env
chown mongodb:mongodb /srv/app/app.env
cat > /home/player/README.md <<'MD'
# Lock down MongoDB (Lena)

  node1       127.0.0.1:27017 (and every other interface), config /etc/mongodb/nodes/node1.conf
  admin       admin / Verdant-Admin-2026          role root (admin db)
  app         verdant_app / Verdant-App-2026      read+write verdant only. Connection string: /srv/app/app.env
  dashboard   verdant_ro / Verdant-RO-2026        read verdant only (same authSource as the app)
  billing     the billing db is finance-only: neither app nor dashboard may read it
MD
chown mongodb:mongodb /home/player/README.md
