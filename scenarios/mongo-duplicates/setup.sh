#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
db_start
js <<'JS' >/dev/null
const u = db.getSiblingDB("app").users;
const docs = [];
const base = Date.now();
for (let i = 0; i < 20000; i++) docs.push({ email: `user${i}@example.com`, name: `User ${i}`, updatedAt: new Date(base - Math.random() * 365 * 864e5) });
// 400 people signed up 2-3 times, with different letter case; the newest copy is marked keep:true (hidden from the task)
for (let i = 0; i < 400; i++) {
  const e = `user${i * 37}@example.com`;
  const copies = 1 + (i % 2) + 1;
  for (let k = 0; k < copies; k++) {
    const variant = k % 2 ? e.toUpperCase() : e.replace(/^u/, "U");
    docs.push({ email: variant, name: `User ${i * 37} (dup ${k})`, updatedAt: new Date(base - (k + 2) * 864e5 * 400 - i) });
  }
}
// make sure the original (lower-case) doc is the newest for half of them, and an upper-case dup for the other half
u.insertMany(docs);
u.find({ email: /@example\.com$/ }).forEach(() => {});
const groups = u.aggregate([{ $sort: { updatedAt: -1 } }, { $group: { _id: { $toLower: "$email" }, ids: { $push: "$_id" }, n: { $sum: 1 } } }, { $match: { n: { $gt: 1 } } }]).toArray();
groups.forEach((g, i) => {
  if (i % 2) { // promote a duplicate to newest
    u.updateOne({ _id: g.ids[g.ids.length - 1] }, { $set: { updatedAt: new Date(base + 1000 + i) } });
  }
});
const again = u.aggregate([{ $sort: { updatedAt: -1 } }, { $group: { _id: { $toLower: "$email" }, ids: { $push: "$_id" }, n: { $sum: 1 } } }, { $match: { n: { $gt: 1 } } }]).toArray();
db.getSiblingDB("sadgrade").expected.insertMany(again.map(g => ({ _id: g.ids[0], email: g._id })));
JS
db_stop
