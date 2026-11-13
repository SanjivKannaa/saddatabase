#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
mkdir -p /srv/wal_archive /backups/nightly && chown postgres:postgres /srv/wal_archive /backups/nightly
node_init 1 17 "wal_level = replica" "archive_mode = on" \
  "archive_command = 'test ! -f /srv/wal_archive/%f && cp %p /srv/wal_archive/%f'" \
  "log_statement = 'mod'   # Tomás: so we can see who changed what"
load_parcels 1 >/dev/null
# 02:00 nightly base backup
runuser -u postgres -- pg_basebackup -p 5432 -D /backups/nightly -Ft -z -X stream -c fast
APP() { PGPASSWORD=Parcel-App-2026 psql -X -q -h 127.0.0.1 -p 5432 -U parcels_app -d parcels "$@" >/dev/null; }
# today: new shipments, status changes, tracking events, new customers, WAL switches
for b in 1 2 3; do
  APP <<'SQL'
INSERT INTO customers (name, email, city) SELECT 'New customer ' || g, 'n' || g || '-' || floor(random()*1e6) || '@parcel.test', 'Lisbon' FROM generate_series(1, 20) g;
INSERT INTO shipments (customer_id, tracking_no, status, weight_g)
  SELECT 1 + floor(random()*2000)::int, 'PT' || lpad((floor(random()*1e9))::text, 9, '0'), 'label_created', 100 + floor(random()*5000)::int FROM generate_series(1, 150);
UPDATE shipments SET status = 'in_transit' WHERE status = 'label_created' AND id % 4 = 0;
UPDATE shipments SET status = 'delivered' WHERE status = 'in_transit' AND id % 7 = 0;
INSERT INTO tracking_events (shipment_id, event) SELECT id, 'in_hub' FROM shipments WHERE status = 'in_transit' ORDER BY id DESC LIMIT 100;
SQL
  nq 1 "select pg_switch_wal()" >/dev/null
done
sleep 1.2
tsum 1 shipments > /opt/sad/shipments.sum
sleep 1.2
# 15:47 -- the accident
APP -c "DELETE FROM shipments"
sleep 1.2
# life goes on
APP <<'SQL'
INSERT INTO tracking_events (shipment_id, event) SELECT 30000 - g, 'out_for_delivery' FROM generate_series(1, 120) g;
UPDATE customers SET city = 'Porto' WHERE id % 50 = 0;
INSERT INTO customers (name, email, city) VALUES ('Late customer', 'late@parcel.test', 'Faro');
SQL
tsum 1 tracking_events > /opt/sad/tracking_events.sum
tsum 1 customers > /opt/sad/customers.sum
nq 1 "select pg_switch_wal()" >/dev/null
for i in $(seq 60); do [ "$(nq 1 "select last_archived_wal = pg_walfile_name(pg_current_wal_lsn() - 1) from pg_stat_archiver")" = t ] && break; sleep 0.5; done
nq 1 "checkpoint" >/dev/null
node_stop 1
chmod -R a+rX /backups
cat > /var/lib/postgresql/README.md <<'MD'
# Incident: parcels.shipments emptied (prod)

  prod       node1, 127.0.0.1:5432, /srv/pg/node1     (node1 = superuser psql)
  backup     /backups/nightly/{base.tar.gz,pg_wal.tar.gz}   pg_basebackup -Ft -z -X stream, 02:00
  archive    /srv/wal_archive                          (node1's archive_command copies every WAL segment here)
  log        /var/log/postgresql/node1.log              (log_statement = 'mod')
  spare      /srv/pg/node2, port 5433 (doesn't exist yet: yours)

  Goal: shipments exactly as before the DELETE. tracking_events and customers keep today's later changes.
MD
chown postgres:postgres /var/lib/postgresql/README.md
