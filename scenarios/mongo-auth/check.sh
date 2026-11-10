#!/bin/bash
. /usr/local/lib/sad/lib.sh
URL='mongodb://app:Ap9-pass-2024@127.0.0.1:27017/shop?authSource=shop'
grep -qx "MONGO_URL=$URL" /srv/app/app.env || fail "/srv/app/app.env was changed"
A='mongodb://admin:Adm1n-lab-pw@127.0.0.1:27017/admin'
[ "$(mongosh --quiet "$A" --eval 'db.runCommand({ping:1}).ok' 2>/dev/null)" = "1" ] || fail "mongod is not running (or the admin login was changed)"
mongosh --quiet mongodb://127.0.0.1:27017/shop --eval 'db.orders.countDocuments()' >/dev/null 2>&1 && fail "access control is off: anyone can read shop"
out=$(mongosh --quiet "$URL" --eval 'db.orders.insertOne({sku: "graded"}); db.orders.countDocuments({sku: "graded"})' 2>&1 | tail -1)
[[ "$out" =~ ^[0-9]+$ ]] || fail "the app still can't write to shop: $(echo "$out" | head -1)"
roles=$(mongosh --quiet "$A" --eval 'JSON.stringify(db.getSiblingDB("shop").getUser("app").roles)' 2>/dev/null)
echo "$roles" | grep -qE '"db":"(admin|config|local)"|AnyDatabase|"root"|cluster' && fail "app has more than it needs: $roles"
pass "the app authenticates against shop and can read and write it; roles: $roles"
