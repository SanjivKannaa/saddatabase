#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
NODE_LOCALE=C node_init 1 16 "shared_preload_libraries = 'pg_stat_statements'" "# TODO ask someone what this does" "work_mem = 16MB"
load_parcels 1
ns 1 -d parcels <<'SQL'
CREATE EXTENSION pg_trgm;
CREATE EXTENSION pg_stat_statements;
CREATE INDEX customers_name_trgm ON customers USING gin (name gin_trgm_ops);
SQL
# PGDG's 16.16 build stamps an unknown "pg_attver" option on every column created in a user database, which
# 17's pg_upgrade then can't restore (packaging quirk, not part of the lesson): strip it from user columns.
ns 1 -d parcels -c "UPDATE pg_attribute SET attoptions = NULL WHERE attrelid >= 16384 AND attoptions::text LIKE '%pg_attver%'"
tsum 1 shipments > /opt/sad/shipments.sum
tsum 1 customers > /opt/sad/customers.sum
node_stop 1
cat > /var/lib/postgresql/README.md <<'MD'
# Maintenance window: PostgreSQL 16 -> 17 (Dana)

  old     node1, PostgreSQL 16, /srv/pg/node1, port 5432      binaries /usr/lib/postgresql/16/bin
  new     PostgreSQL 17 in /srv/pg/node2, must end up on 5432 binaries /usr/lib/postgresql/17/bin
  app     parcels_app (password unchanged), host=127.0.0.1 port=5432 dbname=parcels. Stopped for now.

  The app uses the search index on customers.name (pg_trgm), and Tomás's dashboard reads pg_stat_statements.
MD
chown postgres:postgres /var/lib/postgresql/README.md
