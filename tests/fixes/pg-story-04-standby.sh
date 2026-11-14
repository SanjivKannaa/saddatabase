node1 <<'SQL'
ALTER SYSTEM SET max_wal_senders = 10;
CREATE ROLE replicator LOGIN REPLICATION PASSWORD 'Repl-Parcel-2026';
SQL
echo "host  replication  replicator  127.0.0.1/32  scram-sha-256" >> /srv/pg/node1/pg_hba.conf
sudo systemctl restart postgresql@node1
PGPASSWORD=Repl-Parcel-2026 pg_basebackup -h 127.0.0.1 -p 5432 -U replicator -D /srv/pg/node2 -X stream -R -C -S node2 -c fast
printf "port = 5433\ncluster_name = 'node2'\n" >> /srv/pg/node2/postgresql.auto.conf
sudo systemctl start postgresql@node2
