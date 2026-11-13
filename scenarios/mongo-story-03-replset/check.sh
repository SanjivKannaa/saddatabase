#!/bin/bash
. /usr/local/lib/sad/lib.sh
export SAD_USER=admin SAD_PASS=Verdant-Admin-2026
for n in 1 2 3; do
  [ "$(mq $n 'db.runCommand({ping: 1}).ok')" = 1 ] || fail "node$n (port $(nport $n)) isn't answering, or admin can't log in to it (a member that hasn't synced yet has no users)"
done
mjs 1 <<'JS' || exit 1
const fail = m => { print('FAIL: ' + m); quit(1); };
for (const p of [27017, 27018, 27019]) {
  const c = connect('mongodb://admin:Verdant-Admin-2026@127.0.0.1:' + p + '/admin?authSource=admin&directConnection=true');
  const o = c.adminCommand({ getCmdLineOpts: 1 }).parsed;
  if (((o.replication || {}).replSetName) !== 'rs0') fail('port ' + p + ' isn\'t started with replSetName rs0');
  if (!((o.security || {}).keyFile)) fail('port ' + p + ' has no security.keyFile: members must authenticate to each other');
}
let st; try { st = rs.status(); } catch (e) { fail('rs.status() fails: ' + e.message + ' (was the set initiated?)'); }
if (st.set !== 'rs0') fail('the replica set is called ' + st.set + ', not rs0');
const conf = rs.conf();
if (conf.members.length !== 3) fail('rs0 has ' + conf.members.length + ' members, not 3');
for (const m of conf.members) {
  if (m.arbiterOnly) fail(m.host + ' is an arbiter: all three must hold data');
  if (m.votes !== 1) fail(m.host + ' has ' + m.votes + ' votes');
  if (!/^(127\.0\.0\.1|localhost):2701[789]$/.test(m.host)) fail('member host ' + m.host + ' isn\'t an address the members listen on');
}
let ok = false;
for (let i = 0; i < 40 && !ok; i++) {
  st = rs.status();
  ok = st.members.filter(m => m.stateStr === 'PRIMARY').length === 1 && st.members.filter(m => m.stateStr === 'SECONDARY' && m.health === 1).length === 2;
  if (!ok) sleep(500);
}
if (!ok) fail('rs0 isn\'t one PRIMARY + two healthy SECONDARYs: ' + st.members.map(m => m.name + ' ' + m.stateStr).join(', '));
const want = 60000;
const p = connect('mongodb://admin:Verdant-Admin-2026@127.0.0.1:27017,127.0.0.1:27018,127.0.0.1:27019/verdant?authSource=admin&replicaSet=rs0');
try { p.sad_probe.insertOne({ t: new Date() }, { writeConcern: { w: 'majority', wtimeout: 5000 } }); }
catch (e) { fail('a w:majority write doesn\'t complete within 5 s: ' + e.message); }
p.sad_probe.drop({ writeConcern: { w: 'majority' } });
if (p.readings.countDocuments() !== want) fail('verdant.readings has ' + p.readings.countDocuments() + ' documents on the primary, it had ' + want);
for (const port of [27017, 27018, 27019]) {
  const c = connect('mongodb://admin:Verdant-Admin-2026@127.0.0.1:' + port + '/verdant?authSource=admin&directConnection=true&readPreference=secondaryPreferred');
  const n = c.readings.countDocuments();
  if (n !== want) fail('port ' + port + ' has ' + n + ' readings, not ' + want);
}
JS
. /srv/app/app.env
grep -q 'replicaSet=rs0' /srv/app/app.env || fail "the app's connection string was changed"
out=$(mongosh --quiet "$MONGO_URL" --eval 'db.hello().setName + " " + db.devices.countDocuments()' 2>&1 | tail -1)
[ "$out" = "rs0 600" ] || fail "the app's connection string doesn't work: $out"
pass "rs0: one primary, two secondaries, keyfile auth, every reading on every member, majority writes OK, the app connects"
