#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
node_init 1 "setParameter:\n  ttlMonitorSleepSecs: 5"
load_verdant 1
mq 1 "db.getSiblingDB('admin').createUser({ user: 'admin', pwd: 'Verdant-Admin-2026', roles: [{ role: 'root', db: 'admin' }] })" >/dev/null
mq 1 "db.getSiblingDB('verdant').createUser({ user: 'verdant_app', pwd: 'Verdant-App-2026', roles: [{ role: 'readWrite', db: 'verdant' }] })" >/dev/null
date +%s > /opt/sad/built
# the last 60 days of readings, all with string timestamps since ingest v2 (older Date readings already expired)
mjs 1 verdant <<JS >/dev/null
db.readings.drop();
const built = $(cat /opt/sad/built) * 1000;
for (let b = 0; b < 60; b++) {
  const batch = [];
  for (let j = 0; j < 1000; j++) { const i = b * 1000 + j;
    batch.push({ device: 'dev-' + String(1 + i % 600).padStart(4, '0'), ts: new Date(built - i * 86400).toISOString(), value: 15 + (i * 37 % 200) / 10 }); }
  db.readings.insertMany(batch);
}
db.readings.createIndex({ device: 1, ts: -1 });
db.readings.createIndex({ ts: 1 }, { name: 'ts_ttl', expireAfterSeconds: 25920000 });
JS
node_stop 1
printf 'security:\n  authorization: enabled\n' >> /etc/mongodb/nodes/node1.conf
cat > /srv/app/ingest.js <<'JS'
// Verdant ingest v2 (Kofi): takes gateway batches and stores them. Runs ~20 s, then the scheduler starts it again.
const v = db.getSiblingDB('verdant');
for (let k = 0; k < 20; k++) {
  const now = Date.now();
  v.readings.insertMany(Array.from({ length: 5 }, (_, i) => ({
    device: 'dev-' + String(1 + (now / 1000 + i) % 600 | 0).padStart(4, '0'),
    ts: new Date().toISOString(),                // v2: ISO strings are easier to debug
    value: 18 + i, source: 'gateway'
  })));
  sleep(1000);
}
JS
chown mongodb:mongodb /srv/app/ingest.js
cat > /home/player/README.md <<'MD'
# Readings older than 30 days aren't expiring (Ana)

  node1     127.0.0.1:27017, db verdant, collection readings     admin / Verdant-Admin-2026 (authSource admin)
  ingest    /srv/app/ingest.js (re-read every ~20 s by the scheduler)
  retention 30 days, TTL index on ts. This box runs the TTL monitor every 5 s.
MD
chown mongodb:mongodb /home/player/README.md
