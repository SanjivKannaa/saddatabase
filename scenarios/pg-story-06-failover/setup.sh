#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
node_init 1 17 "wal_keep_size = 256MB"
load_parcels 1 >/dev/null
ns 1 -c "CREATE ROLE replicator LOGIN REPLICATION PASSWORD 'Repl-Parcel-2025'"
echo "host  replication  replicator  127.0.0.1/32  scram-sha-256" >> /srv/pg/node1/pg_hba.conf
nq 1 "select pg_reload_conf()" >/dev/null
for n in 2 3; do
  PGPASSWORD=Repl-Parcel-2025 runuser -u postgres -- pg_basebackup -h 127.0.0.1 -p 5432 -U replicator -D /srv/pg/node$n -X stream -C -S node$n -c fast
  touch /srv/pg/node$n/standby.signal
  cat >> /srv/pg/node$n/postgresql.auto.conf <<CONF
port = $(nport $n)
cluster_name = 'node$n'
primary_conninfo = 'host=127.0.0.1 port=5432 user=replicator password=Repl-Parcel-2025 application_name=node$n'
primary_slot_name = 'node$n'
CONF
  chown postgres:postgres /srv/pg/node$n/standby.signal /srv/pg/node$n/postgresql.auto.conf
done
node_start 2; node_start 3
# last week: password rotation. node2 got the new one, node3 didn't.
ns 1 -c "ALTER ROLE replicator PASSWORD 'Repl-Parcel-2026'"
sed -i 's/Repl-Parcel-2025/Repl-Parcel-2026/' /srv/pg/node2/postgresql.auto.conf
nq 2 "select pg_reload_conf()" >/dev/null
node_stop 3; node_start 3          # reconnects with the old password: fails from now on
for i in $(seq 40); do [ "$(nq 1 "select count(*) from pg_stat_replication where application_name = 'node2' and state = 'streaming'")" = 1 ] && break; sleep 0.5; done
# ansible ships one postgresql.conf to every node
for n in 1 2 3; do echo "synchronous_standby_names = 'node2'   # same file on every node (ansible)" >> /srv/pg/node$n/postgresql.conf; done
for n in 1 2 3; do nq $n "select pg_reload_conf()" >/dev/null; done
# a week of deliveries that only node1 and node2 have
ns 1 -d parcels <<'SQL'
INSERT INTO shipments (customer_id, tracking_no, status, weight_g, created_at)
  SELECT 1 + (g * 13) % 2000, 'PW' || lpad(g::text, 9, '0'), 'delivered', 500 + g % 3000, now() - make_interval(hours => g / 10) FROM generate_series(1, 1500) g;
SQL
nq 1 "checkpoint" >/dev/null; sleep 1
node_stop 3; node_stop 2; node_stop 1
echo "DB_PORT=5432" > /srv/app/db.env; chown postgres:postgres /srv/app/db.env
cat > /var/lib/postgresql/README.md <<'MD'
# 03:12 node1 is down (Inês)

  node1   primary  127.0.0.1:5432   host offline (power supply). I'll let you know when it's back.
  node2   standby  127.0.0.1:5433   synchronous standby of node1
  node3   standby  127.0.0.1:5434   async standby of node1
  app     /srv/app/db.env (DB_PORT) -- the drivers' app re-reads it on every write
  repl    role replicator, password Repl-Parcel-2026 (rotated last week)
MD
chown postgres:postgres /var/lib/postgresql/README.md
