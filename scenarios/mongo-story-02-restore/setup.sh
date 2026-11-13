#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
node_init 1
load_verdant 1
mq 1 "db.getSiblingDB('admin').createUser({ user: 'admin', pwd: 'Verdant-Admin-2026', roles: [{ role: 'root', db: 'admin' }] })" >/dev/null
mq 1 "db.getSiblingDB('verdant').createUser({ user: 'verdant_app', pwd: 'Verdant-App-2026', roles: [{ role: 'readWrite', db: 'verdant' }] })" >/dev/null
node_stop 1
printf 'security:\n  authorization: enabled\n' >> /etc/mongodb/nodes/node1.conf
node_start 1
export SAD_USER=admin SAD_PASS=Verdant-Admin-2026
U='mongodb://admin:Verdant-Admin-2026@127.0.0.1:27017/?authSource=admin'
# 02:00 nightly dump
mongodump --quiet --uri "$U" --db verdant --archive=/backups/verdant-nightly.archive.gz --gzip
chown mongodb:mongodb /backups/verdant-nightly.archive.gz
# today, before the accident: Lisbon firmware upgrade, new Braga devices
mjs 1 verdant <<'JS' >/dev/null
db.devices.updateMany({ site: 'Lisbon' }, { $set: { firmware: '3.0.0', upgraded: new Date('2026-11-14T08:10:00Z') } });
db.devices.insertMany(Array.from({ length: 20 }, (_, i) => ({ _id: 'dev-' + (601 + i), site: 'Braga', kind: 'co2', firmware: '3.0.0', status: 'active', installed: new Date('2026-11-14T08:30:00Z') })));
JS
# 09:42 the accident
mq 1 "db.devices.deleteMany({ site: 'Porto' }).deletedCount" verdant > /opt/sad/deleted
# after: Faro devices decommissioned, one more registration
mjs 1 verdant <<'JS' >/dev/null
db.devices.updateMany({ site: 'Faro', kind: 'soil' }, { $set: { status: 'maintenance' } });
db.devices.insertOne({ _id: 'dev-0621', site: 'Evora', kind: 'temp', firmware: '3.0.0', status: 'active', installed: new Date('2026-11-14T10:05:00Z') });
JS
# what devices must look like afterwards (computed on a scratch db, then dropped)
mongorestore --quiet --uri "$U" --archive=/backups/verdant-nightly.archive.gz --gzip --nsInclude 'verdant.devices' --nsFrom 'verdant.devices' --nsTo 'sadexp.restore'
mjs 1 <<'JS' > /opt/sad/expected
const x = db.getSiblingDB('sadexp');
db.getSiblingDB('verdant').devices.aggregate([{ $out: { db: 'sadexp', coll: 'devices' } }]);
x.restore.aggregate([{ $match: { site: 'Porto', status: { $ne: 'decommissioned' } } }, { $merge: { into: 'devices', whenMatched: 'keepExisting', whenNotMatched: 'insert' } }]);
print(x.runCommand({ dbHash: 1, collections: ['devices'] }).collections.devices);
print(x.devices.countDocuments({ site: 'Porto' }));
print(x.restore.countDocuments({ site: 'Porto', status: 'decommissioned' }));
x.dropDatabase();
JS
mq 1 "db.getCollectionNames().sort().join(',')" verdant > /opt/sad/collections
node_stop 1
cat > /home/player/README.md <<'MD'
# Incident: Porto devices deleted (Kofi, 09:42)

  node1     127.0.0.1:27017, db verdant      login: admin / Verdant-Admin-2026 (authSource admin)
  ran       db.devices.deleteMany({ site: 'Porto' })
  meant     db.devices.deleteMany({ site: 'Porto', status: 'decommissioned' })
  backup    /backups/verdant-nightly.archive.gz   (mongodump --db verdant --archive --gzip, 02:00)
  today     Lisbon firmware upgrade (08:10), new Braga devices (08:30), Faro maintenance (after 09:42)
MD
chown mongodb:mongodb /home/player/README.md
