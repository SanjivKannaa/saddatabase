#!/bin/bash
. /usr/local/lib/sad/lib.sh
export SAD_USER=admin SAD_PASS=Verdant-Admin-2026
[ "$(mq 1 'db.runCommand({ping: 1}).ok')" = 1 ] || fail "node1 isn't running (or admin can't log in)"
mjs 1 verdant <<JS || exit 1
const fail = m => { print('FAIL: ' + m); quit(1); };
const ttl = db.readings.getIndexes().find(i => i.expireAfterSeconds !== undefined);
if (!ttl) fail('readings has no TTL index any more');
if (JSON.stringify(ttl.key) !== JSON.stringify({ ts: 1 })) fail('the TTL index is on ' + JSON.stringify(ttl.key) + ', not { ts: 1 }');
if (ttl.expireAfterSeconds !== 2592000) fail('the TTL index expires documents after ' + ttl.expireAfterSeconds + ' s (' + Math.round(ttl.expireAfterSeconds / 86400) + ' days), not 2592000 (30 days)');
if (!db.readings.getIndexes().some(i => JSON.stringify(i.key) === JSON.stringify({ device: 1, ts: -1 }))) fail('the { device: 1, ts: -1 } index is gone');
const types = db.readings.aggregate([{ \$group: { _id: { \$type: '\$ts' }, n: { \$sum: 1 } } }]).toArray().filter(t => t._id !== 'date');
if (types.length) fail('some ts values still aren\'t dates: ' + types.map(t => t.n + ' x ' + t._id).join(', ') + ' (the TTL monitor ignores them)');
// the ingest job writes dates now?
let fresh = null;
for (let i = 0; i < 50 && !fresh; i++) { fresh = db.readings.findOne({ source: 'gateway', ts: { \$type: 'date', \$gte: new Date(Date.now() - 15000) } }); if (!fresh) sleep(500); }
if (!fresh) fail('no fresh readings with a date ts from the ingest job: fix /srv/app/ingest.js (and keep it running)');
const s = db.readings.countDocuments({ ts: { \$type: 'string' } });
if (s) fail(s + ' string timestamps appeared again (the ingest job)');
// old ones gone (allow the TTL monitor a few passes)
const cutoff = () => new Date(Date.now() - 2592000 * 1000 - 120 * 1000);
let old = 0;
for (let i = 0; i < 30; i++) { old = db.readings.countDocuments({ ts: { \$lt: cutoff() } }); if (!old) break; sleep(1000); }
if (old) fail(old + ' readings older than 30 days are still there');
// the last 30 days stayed: count the generated readings that should still be inside the window
const built = $(cat /opt/sad/built) * 1000, now = Date.now();
const lo = now - 29 * 86400e3, hi = Math.min(now - 3600e3, built);
let want = 0; for (let i = 0; i < 60000; i++) { const t = built - i * 86400; if (t >= lo && t <= hi) want++; }
const have = db.readings.countDocuments({ source: { \$exists: false }, ts: { \$gte: new Date(lo), \$lte: new Date(hi) } });
if (have < want) fail('only ' + have + ' of the ' + want + ' readings from the last 29 days are left: recent readings must stay');
print('PASS: every ts is a date, the TTL index expires after 30 days, nothing older remains, the last 30 days (' + have + ' readings) and fresh ingest data are intact');
JS
