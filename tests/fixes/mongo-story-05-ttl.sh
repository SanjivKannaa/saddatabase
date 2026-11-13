U='mongodb://admin:Verdant-Admin-2026@127.0.0.1:27017/verdant?authSource=admin'
sed -i 's/ts: new Date().toISOString()/ts: new Date()/' /srv/app/ingest.js
sleep 25
mongosh "$U" --quiet <<'JS'
db.runCommand({ collMod: 'readings', index: { keyPattern: { ts: 1 }, expireAfterSeconds: 2592000 } })
db.readings.updateMany({ ts: { $type: 'string' } }, [{ $set: { ts: { $toDate: '$ts' } } }])
JS
sleep 10
