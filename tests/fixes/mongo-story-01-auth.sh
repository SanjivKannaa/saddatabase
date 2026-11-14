node1 --quiet <<'JS'
use admin
db.createUser({ user: 'admin', pwd: 'Verdant-Admin-2026', roles: [{ role: 'root', db: 'admin' }] })
use verdant
db.createUser({ user: 'verdant_app', pwd: 'Verdant-App-2026', roles: [{ role: 'readWrite', db: 'verdant' }] })
db.createUser({ user: 'verdant_ro', pwd: 'Verdant-RO-2026', roles: [{ role: 'read', db: 'verdant' }] })
JS
sed -i 's/bindIp: 0.0.0.0/bindIp: 127.0.0.1/' /etc/mongodb/nodes/node1.conf
printf 'security:\n  authorization: enabled\n' >> /etc/mongodb/nodes/node1.conf
sudo systemctl restart mongod@node1
