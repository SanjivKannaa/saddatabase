U='mongodb://admin:Verdant-Admin-2026@127.0.0.1:27017/?authSource=admin'
mongorestore --uri "$U" --archive=/backups/verdant-nightly.archive.gz --gzip \
  --nsInclude 'verdant.devices' --nsFrom 'verdant.devices' --nsTo 'verdant.devices_restore'
mongosh "$U" --quiet <<'JS'
use verdant
db.devices_restore.aggregate([
  { $match: { site: 'Porto', status: { $ne: 'decommissioned' } } },
  { $merge: { into: 'devices', whenMatched: 'keepExisting', whenNotMatched: 'insert' } }
])
db.devices_restore.drop()
JS
