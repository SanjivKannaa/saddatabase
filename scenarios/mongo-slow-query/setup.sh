#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
db_start
js <<'JS' >/dev/null
const d = db.getSiblingDB("shop");
const st = ["pending", "paid", "shipped", "delivered"];
for (let b = 0; b < 30; b++) {
  const docs = [];
  for (let i = 0; i < 10000; i++) docs.push({
    customerId: 1 + Math.floor(Math.random() * 9999), status: st[Math.floor(Math.random() * 4)],
    total: Math.round(Math.random() * 30000) / 100, createdAt: new Date(Date.now() - Math.random() * 730 * 864e5)});
  d.orders.insertMany(docs, { ordered: false });
}
d.orders.createIndex({ status: 1 });
d.orders.createIndex({ createdAt: -1 });
JS
db_stop
