#!/bin/bash
. /usr/local/lib/sad/lib.sh
[ "$(q 'db.runCommand({ping:1}).ok')" = "1" ] || fail "mongod is not running"
r=$(q '
const u = db.getSiblingDB("app").users;
const total = u.countDocuments(), distinct = u.aggregate([{ $group: { _id: { $toLower: "$email" } } }, { $count: "n" }]).toArray()[0].n;
const exp = db.getSiblingDB("sadgrade").expected.find().toArray();
const kept = u.countDocuments({ _id: { $in: exp.map(e => e._id) } });
const idx = u.getIndexes().filter(i => i.unique && JSON.stringify(i.key) === "{\"email\":1}");
const ci = idx.some(i => i.collation && i.collation.strength <= 2);
const allLower = u.countDocuments({ $expr: { $ne: ["$email", { $toLower: "$email" }] } }) === 0;
[total, distinct, kept, exp.length, idx.length, ci, allLower].join(" ")')
read total distinct kept expected nidx ci lower <<< "$r"
[ "$total" = "$distinct" ] || fail "$((total - distinct)) duplicate accounts remain"
[ "$distinct" = "20000" ] || fail "expected 20000 distinct users, found $distinct (deleted too much?)"
[ "$kept" = "$expected" ] || fail "for $((expected - kept)) of $expected emails you kept an older copy, not the most recently updated one"
[ "$nidx" -ge 1 ] || fail "no unique index on { email: 1 }: the next duplicate will get in"
if [ "$ci" != "true" ]; then
  [ "$lower" = "true" ] || fail "the unique index is case-sensitive and emails are mixed-case: Bob@x and bob@x could both be inserted"
  echo "note: emails are normalised to lower case; make sure the app lower-cases new signups too"
fi
pass "20000 unique users, newest copies kept, and a unique index guards email"
