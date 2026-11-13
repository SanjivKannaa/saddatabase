until [ -f /etc/sad/node1.dead ]; do sleep 1; done
node2 -c 'select pg_promote()'
node2 <<'SQL'
ALTER SYSTEM SET synchronous_standby_names = 'ANY 1 (node1, node3)';
SELECT pg_reload_conf();
SELECT pg_create_physical_replication_slot('node1');
SELECT pg_create_physical_replication_slot('node3');
SQL
sed -i 's/^DB_PORT=.*/DB_PORT=5433/' /srv/app/db.env
cat >> /srv/pg/node3/postgresql.auto.conf <<'CONF'
primary_conninfo = 'host=127.0.0.1 port=5433 user=replicator password=Repl-Parcel-2026 application_name=node3'
primary_slot_name = 'node3'
CONF
node3 -c 'select pg_reload_conf()'
until [ -f ~/INES-node1-is-back.md ]; do sleep 1; done
pg_rewind -D /srv/pg/node1 --source-server='port=5433 user=postgres dbname=postgres'
cat >> /srv/pg/node1/postgresql.auto.conf <<'CONF'
port = 5432
cluster_name = 'node1'
primary_conninfo = 'host=127.0.0.1 port=5433 user=replicator password=Repl-Parcel-2026 application_name=node1'
primary_slot_name = 'node1'
CONF
touch /srv/pg/node1/standby.signal
dbctl start node1
sleep 3
