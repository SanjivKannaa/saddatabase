#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
db_start
js <<'JS' >/dev/null
db.getSiblingDB("admin").createUser({user: "admin", pwd: "Adm1n-lab-pw", roles: ["root"]});
db.getSiblingDB("admin").createUser({user: "app", pwd: "Ap9-pass-2024", roles: [{role: "read", db: "shop"}]});
db.getSiblingDB("shop").orders.insertMany(Array.from({length: 250}, (_, i) => ({sku: "SKU-" + i, qty: i % 7})));
JS
db_stop
printf 'security:\n  authorization: enabled\n' >> /etc/mongodb/mongod.conf
mkdir -p /srv/app
echo 'MONGO_URL=mongodb://app:Ap9-pass-2024@127.0.0.1:27017/shop?authSource=shop' > /srv/app/app.env
echo 'admin user: admin   password: Adm1n-lab-pw   auth db: admin
mongosh -u admin -p Adm1n-lab-pw --authenticationDatabase admin' > /home/player/admin.txt
chown mongodb:mongodb /home/player/admin.txt
