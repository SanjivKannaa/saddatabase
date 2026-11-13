#!/bin/bash
. /usr/local/lib/sad/lib.sh
export SAD_USER=admin SAD_PASS=Verdant-Admin-2026
[ "$(mq 1 'db.runCommand({ping: 1}).ok')" = 1 ] || fail "node1 isn't running (or admin can't log in)"
read -r want_hash want_porto want_decom < <(paste -sd' ' /opt/sad/expected)
mjs 1 verdant <<JS || exit 1
const fail = m => { print('FAIL: ' + m); quit(1); };
const porto = db.devices.countDocuments({ site: 'Porto' });
const decom = db.devices.countDocuments({ site: 'Porto', status: 'decommissioned' });
if (porto === 0) fail('there are still no Porto devices');
if (db.devices.countDocuments({ site: 'Lisbon', firmware: { \$ne: '3.0.0' } }) > 0) fail("Lisbon devices lost this morning's firmware upgrade: the restore overwrote today's changes");
if (db.devices.countDocuments({ _id: { \$in: ['dev-601', 'dev-620', 'dev-0621'] } }) < 3) fail('devices registered today are gone: the restore replaced the collection');
if (db.devices.countDocuments({ site: 'Faro', kind: 'soil', status: { \$ne: 'maintenance' } }) > 0) fail("the Faro devices put in maintenance after the accident were reverted");
if (decom > 0) fail(decom + ' decommissioned Porto devices came back: those were meant to be deleted');
if (porto < $want_porto) fail('only ' + porto + ' of the $want_porto active Porto devices are back');
const h = db.runCommand({ dbHash: 1, collections: ['devices'] }).collections.devices;
if (h !== '$want_hash') fail('verdant.devices has the right counts but not the right contents (Porto devices should be exactly as in the dump; everything else as it is today)');
if (!db.devices.getIndexes().some(i => JSON.stringify(i.key) === JSON.stringify({ site: 1, status: 1 }))) fail('the { site: 1, status: 1 } index on devices is gone');
const cols = db.getCollectionNames().sort().join(',');
if (cols !== '$(cat /opt/sad/collections)') fail('verdant has collections it didn\'t have before (' + cols + '): drop the temporary ones');
print('PASS: ' + porto + ' active Porto devices restored from the dump, decommissioned ones still gone, today\'s changes intact, no leftovers');
JS
