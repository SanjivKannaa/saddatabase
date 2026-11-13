#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
head -c 756 /dev/urandom | base64 -w0 > /etc/mongodb/keyfile
cp /etc/mongodb/keyfile /etc/mongodb/keyfile-node2
chown mongodb:mongodb /etc/mongodb/keyfile /etc/mongodb/keyfile-node2; chmod 400 /etc/mongodb/keyfile /etc/mongodb/keyfile-node2
# first: a standalone node1 with data and users
node_init 1
load_verdant 1
mq 1 "db.getSiblingDB('admin').createUser({ user: 'admin', pwd: 'Verdant-Admin-2026', roles: [{ role: 'root', db: 'admin' }] })" >/dev/null
mq 1 "db.getSiblingDB('verdant').createUser({ user: 'verdant_app', pwd: 'Verdant-App-2026', roles: [{ role: 'readWrite', db: 'verdant' }] })" >/dev/null
node_stop 1
# Kofi's replica set: P, S, A
for n in 1 2 3; do
  kf=/etc/mongodb/keyfile; [ $n = 2 ] && kf=/etc/mongodb/keyfile-node2
  node_conf $n "security:\n  authorization: enabled\n  keyFile: $kf" "replication:\n  replSetName: rs0"
  node_start $n
done
export SAD_USER=admin SAD_PASS=Verdant-Admin-2026
mq 1 "rs.initiate({ _id: 'rs0', members: [{ _id: 0, host: '127.0.0.1:27017', priority: 2 }, { _id: 1, host: '127.0.0.1:27018' }] }).ok" >/dev/null
for i in $(seq 60); do [ "$(mq 1 'rs.status().members.filter(m => m.stateStr === "SECONDARY").length')" = 1 ] && [ "$(mq 1 'db.hello().isWritablePrimary')" = true ] && break; sleep 1; done
mq 1 "db.adminCommand({ setDefaultRWConcern: 1, defaultWriteConcern: { w: 1 } }).ok" >/dev/null
mq 1 "rs.addArb('127.0.0.1:27019').ok" >/dev/null
for i in $(seq 60); do [ "$(mq 1 'rs.status().members.filter(m => m.stateStr === "ARBITER").length')" = 1 ] && break; sleep 1; done
mq 1 "db.getSiblingDB('verdant').readings.countDocuments()" > /opt/sad/readings0
sleep 2
for n in 3 2 1; do node_stop $n; done
# last night: Kofi "debugged" node2's keyfile
chmod 644 /etc/mongodb/keyfile-node2
cat > /opt/sad/ingest.js <<'JS'
// the ingest app: one reading every 0.3 s with w: 'majority'; successes are logged
const fs = require('fs');
const v = db.getSiblingDB('verdant');
let n = 0;
while (true) {
  n++;
  try {
    v.readings.insertOne({ device: 'dev-' + String(1 + n % 600).padStart(4, '0'), ts: new Date(), value: 20 + n % 7 }, { writeConcern: { w: 'majority', wtimeout: 3000 } });
    fs.appendFileSync('/opt/sad/ingest.log', Math.floor(Date.now() / 1000) + '\n');
  } catch (e) { }
  sleep(300);
}
JS
cat > /home/player/README.md <<'MD'
# Readings not saving since ~00:00 (Ana)

  rs0     node1 127.0.0.1:27017  primary
          node2 127.0.0.1:27018  secondary   <- down since last night, won't start
          node3 127.0.0.1:27019  arbiter
  admin   admin / Verdant-Admin-2026 (authSource admin)
  ingest  writes readings with w: 'majority', connection string: replicaSet=rs0
MD
chown mongodb:mongodb /home/player/README.md
