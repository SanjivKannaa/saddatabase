#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
mkdir -p /srv/wal_archive && chown postgres:postgres /srv/wal_archive
node_init 1 17 "max_wal_size = 128MB" "min_wal_size = 32MB" "archive_mode = on" \
  "archive_command = 'test ! -f /srv/wal_archive/%f && cp %p /srv/wal_archive/%f'"
load_parcels 1 >/dev/null
ns 1 -c "CREATE ROLE replicator LOGIN REPLICATION PASSWORD 'Repl-Parcel-2026'"
echo "host  replication  replicator  127.0.0.1/32  scram-sha-256" >> /srv/pg/node1/pg_hba.conf
nq 1 "select pg_reload_conf()" >/dev/null
# node2: the standby from last chapter
PGPASSWORD=Repl-Parcel-2026 runuser -u postgres -- pg_basebackup -h 127.0.0.1 -p 5432 -U replicator -D /srv/pg/node2 -X stream -R -C -S node2 -c fast
printf "port = 5433\ncluster_name = 'node2'\n" >> /srv/pg/node2/postgresql.auto.conf
node_start 2
# node3: tried once, data directory deleted, slot left behind
nq 1 "select pg_create_physical_replication_slot('node3', true)" >/dev/null
# Tomás "tidied up /srv": the archive moved, the command didn't
sed -i "s#^archive_command = .*#archive_command = 'test ! -f /srv/wal-archive/%f \&\& cp %p /srv/wal-archive/%f'#" /srv/pg/node1/postgresql.conf
nq 1 "select pg_reload_conf()" >/dev/null
# months of traffic
ns 1 -d parcels <<'SQL'
CREATE TABLE label_batches AS SELECT g AS id, repeat(md5(g::text), 16) AS payload FROM generate_series(1, 450000) g;
DROP TABLE label_batches;
SQL
nq 1 "checkpoint" >/dev/null
sleep 2
node_stop 2; node_stop 1
cat > /var/lib/postgresql/README.md <<'MD'
# Disk alert: node1 pg_wal (Inês)

  node1   primary, 127.0.0.1:5432, /srv/pg/node1       pg_wal budget: way under 1 GB
  node2   standby, 127.0.0.1:5433, /srv/pg/node2       streaming from node1 (slot node2). Keep it working.
  archive /srv/wal_archive                             (where node1's WAL should be archived)

  how big:  node1 -c "select count(*), pg_size_pretty(sum(size)) from pg_ls_waldir()"
MD
chown postgres:postgres /var/lib/postgresql/README.md
