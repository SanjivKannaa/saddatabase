initdb -D /srv/pg/node2 --data-checksums -E UTF8 --locale=C --auth-local=peer --auth-host=scram-sha-256
cat >> /srv/pg/node2/postgresql.conf <<'CONF'
port = 5432
listen_addresses = 'localhost'
shared_preload_libraries = 'pg_stat_statements'
CONF
dbctl stop node1
cd ~
pg_upgrade -b /usr/lib/postgresql/16/bin -B /usr/lib/postgresql/17/bin -d /srv/pg/node1 -D /srv/pg/node2 --link
dbctl start node2
vacuumdb --all --analyze-in-stages
