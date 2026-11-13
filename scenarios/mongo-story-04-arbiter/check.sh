#!/bin/bash
. /usr/local/lib/sad/lib.sh
export SAD_USER=admin SAD_PASS=Verdant-Admin-2026
pp=""
for i in $(seq 40); do
  for n in 1 2 3; do [ "$(mq $n 'db.hello().isWritablePrimary')" = true ] && { pp=$(nport $n); break 2; }; done; sleep 0.5
done
[ -n "$pp" ] || fail "rs0 has no primary (node1 state: $(mq 1 'rs.status().myState' || echo down))"
R="mongodb://admin:Verdant-Admin-2026@127.0.0.1:$pp/admin?authSource=admin&directConnection=true"
cat > /tmp/sad-check.js <<'JS'
const fail = m => { print('FAIL: ' + m); quit(1); };
const conf = rs.conf();
const st0 = rs.status();
const n2 = st0.members.find(m => m.name.endsWith(':27018'));
if (!n2 || n2.health !== 1) fail('node2 (27018) is still down: dbctl start node2 and read what it says');
const arb = conf.members.filter(m => m.arbiterOnly);
if (arb.length) fail(arb.map(m => m.host).join(', ') + ' is still an arbiter: replace it with a data-bearing member');
if (conf.members.length !== 3) fail('rs0 has ' + conf.members.length + ' members, not 3');
for (const m of conf.members) if (m.votes !== 1) fail(m.host + ' has ' + m.votes + ' votes');
if (!conf.members.some(m => m.host.endsWith(':27019'))) fail('node3 (27019) isn\'t a member any more: add it back as a data-bearing member');
let st, ok = false;
for (let i = 0; i < 60 && !ok; i++) {
  st = rs.status();
  ok = st.members.filter(m => m.stateStr === 'PRIMARY').length === 1 && st.members.filter(m => m.stateStr === 'SECONDARY' && m.health === 1).length === 2;
  if (!ok) sleep(500);
}
if (!ok) fail('rs0 isn\'t one PRIMARY + two healthy SECONDARYs: ' + st.members.map(m => m.name + ' ' + m.stateStr).join(', '));
const d = db.adminCommand({ getDefaultRWConcern: 1 });
if (!d.defaultWriteConcern || d.defaultWriteConcern.w !== 'majority') fail('the cluster-wide default write concern is ' + JSON.stringify(d.defaultWriteConcern || {}) + ', not { w: "majority" }');
const v = connect('mongodb://admin:Verdant-Admin-2026@127.0.0.1:27017,127.0.0.1:27018,127.0.0.1:27019/verdant?authSource=admin&replicaSet=rs0');
try { v.sad_probe.insertOne({ t: new Date() }, { writeConcern: { w: 'majority', wtimeout: 5000 } }); }
catch (e) { fail('a w:majority write doesn\'t complete within 5 s: ' + e.message); }
v.sad_probe.drop();
const want = v.readings.countDocuments();
const n3 = connect('mongodb://admin:Verdant-Admin-2026@127.0.0.1:27019/verdant?authSource=admin&directConnection=true&readPreference=secondaryPreferred');
let have = 0;
for (let i = 0; i < 20; i++) { have = n3.readings.countDocuments(); if (have >= want - 50) break; sleep(500); }
if (have < want - 50) fail('node3 has ' + have + ' readings, the primary ' + want + ': is it really holding data?');
JS
out=$(mongosh --quiet "$R" --file /tmp/sad-check.js 2>&1); rc=$?
echo "$out" | grep -E '^(FAIL|PASS)' | head -1 | grep -q '^FAIL' && { echo "$out" | grep '^FAIL' | head -1; exit 1; }
[ $rc = 0 ] || fail "couldn't check rs0: $(echo "$out" | tail -1 | cut -c1-200)"
now=$(date +%s)
for i in $(seq 20); do [ "$(awk -v t=$((now - 4)) '$1 >= t' /opt/sad/ingest.log | wc -l)" -ge 3 ] && break; sleep 0.5; now=$(date +%s); done
[ "$(awk -v t=$((now - 5)) '$1 >= t' /opt/sad/ingest.log | wc -l)" -ge 3 ] || fail "the ingest app still isn't saving readings"
pass "rs0 is primary + two data-bearing secondaries (no arbiter), majority is the default write concern, and readings are saving again"
