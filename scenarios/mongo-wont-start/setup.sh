#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
db_start
js 'db.getSiblingDB("inventory").items.insertMany(Array.from({length: 5000}, (_, i) => ({sku: "SKU-" + i, qty: Math.floor(Math.random()*100)})))' >/dev/null
db_stop
sed -i 's|dbPath: /srv/mongo|dbPath: /srv/mongodb|' /etc/mongodb/mongod.conf
sed -i 's|^  port: 27017|\tport: 27017|' /etc/mongodb/mongod.conf
