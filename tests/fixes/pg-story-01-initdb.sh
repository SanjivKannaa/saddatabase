initdb -D /srv/pg/node1 --data-checksums -E UTF8 --locale=C.UTF-8 --auth-local=peer --auth-host=scram-sha-256
cat >> /srv/pg/node1/postgresql.conf <<'CONF'
port = 5432
listen_addresses = 'localhost'
shared_buffers = 256MB
CONF
dbctl start node1
node1 <<'SQL'
CREATE ROLE parcels_owner NOLOGIN;
CREATE ROLE parcels_app LOGIN PASSWORD 'Parcel-App-2026';
CREATE DATABASE parcels OWNER parcels_owner ENCODING 'UTF8';
\c parcels
CREATE SCHEMA app AUTHORIZATION parcels_owner;
GRANT USAGE, CREATE ON SCHEMA app TO parcels_app;
SQL
