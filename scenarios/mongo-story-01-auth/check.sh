#!/bin/bash
. /usr/local/lib/sad/lib.sh
runuser -u mongodb -- dbctl status node1 | grep -q running || fail "node1 isn't running"
runuser -u mongodb -- dbctl restart node1 >/dev/null || fail "node1 doesn't come back after a restart: see /var/log/mongodb/node1.log"
out=$(mongosh --quiet --port 27017 --eval "db.getSiblingDB('verdant').devices.findOne()" 2>&1)
[[ "$out" == *"requires authentication"* || "$out" == *Unauthorized* ]] || fail "an unauthenticated client can still read verdant.devices"
export SAD_USER=admin SAD_PASS=Verdant-Admin-2026
[ "$(mq 1 'db.runCommand({ping: 1}).ok')" = 1 ] || fail "can't log in as admin / Verdant-Admin-2026 (authSource admin)"
mjs 1 <<'JS' || exit 1
const fail = m => { print('FAIL: ' + m); quit(1); };
const opts = db.adminCommand({ getCmdLineOpts: 1 }).parsed;
if ((opts.security || {}).authorization !== 'enabled') fail('security.authorization isn\'t enabled in the config');
const bind = String((opts.net || {}).bindIp || '');
if (bind.split(',').some(a => !['127.0.0.1', 'localhost', '::1'].includes(a.trim()))) fail("bindIp is '" + bind + "': localhost only");
const admin = db.getSiblingDB('admin').getUser('admin');
if (!admin || !admin.roles.some(r => r.role === 'root' && r.db === 'admin')) fail('admin (in the admin db) should have the root role');
const app = db.getSiblingDB('verdant').getUser('verdant_app');
if (!app) fail(db.getSiblingDB('admin').getUser('verdant_app') ? 'verdant_app was created in the admin db, but the app connects with authSource=verdant' : 'there is no user verdant_app in the verdant db');
const ro = db.getSiblingDB('verdant').getUser('verdant_ro');
if (!ro) fail(db.getSiblingDB('admin').getUser('verdant_ro') ? 'verdant_ro was created in the admin db: use the same authSource as the app (verdant)' : 'there is no user verdant_ro in the verdant db');
if (db.getSiblingDB('verdant').readings.countDocuments() !== 60000) fail('verdant.readings should still have 60000 documents');
JS
. /srv/app/app.env
grep -q "verdant_app:Verdant-App-2026@127.0.0.1:27017/verdant?authSource=verdant" /srv/app/app.env || fail "the app's connection string in /srv/app/app.env was changed"
ok() { mongosh --quiet "$1" --eval "$2" >/dev/null 2>&1; }
ok "$MONGO_URL" "db.devices.findOne()" || fail "the app (verdant_app, authSource=verdant) can't read verdant"
ok "$MONGO_URL" "db.sad_probe.insertOne({t: new Date()}); db.sad_probe.drop()" || fail "the app can't write to verdant"
ok "$MONGO_URL" "db.getSiblingDB('billing').invoices.findOne()" && fail "the app can read billing.invoices: verdant only"
ok "$MONGO_URL" "db.getSiblingDB('admin').createUser({user: 'x', pwd: 'x', roles: []})" && fail "the app can create users"
RO='mongodb://verdant_ro:Verdant-RO-2026@127.0.0.1:27017/verdant?authSource=verdant'
ok "$RO" "db.devices.findOne()" || fail "the dashboard (verdant_ro, authSource=verdant) can't read verdant"
ok "$RO" "db.sad_probe.insertOne({t: 1})" && fail "the dashboard user can write to verdant: read-only"
ok "$RO" "db.getSiblingDB('billing').invoices.findOne()" && fail "the dashboard user can read billing"
pass "access control on, localhost only; admin (root), verdant_app (readWrite verdant) and verdant_ro (read verdant) all work as intended"
