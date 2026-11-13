#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
node_init 1 17 "max_prepared_transactions = 5      # Tomás, March: 2PC test for billing" \
  "autovacuum_naptime = 10s" "log_autovacuum_min_duration = 0"
load_parcels 1 >/dev/null
ns 1 -d parcels <<'SQL'
CREATE ROLE reporting LOGIN PASSWORD 'Report-Parcel-2026';
GRANT SELECT ON ALL TABLES IN SCHEMA public TO reporting;
-- March: the billing migration's two-phase commit test, never finished
BEGIN;
INSERT INTO customers (name, email, city) VALUES ('2PC billing test', 'billing-test@parcel.test', 'Lisbon');
PREPARE TRANSACTION 'billing_migration_step3';
SQL
# months of tracking updates since then: dead rows nobody can remove
for i in 1 2 3; do nq 1 "UPDATE tracking_events SET event = event" parcels >/dev/null; done
nq 1 "checkpoint" >/dev/null
node_stop 1
cat > /var/lib/postgresql/README.md <<'MD'
# tracking_events bloat (Inês)

  node1       primary, 127.0.0.1:5432, parcels
  reporting   the BI tool's login (password Report-Parcel-2026), connected all day
  symptoms    node1 -d parcels -c "select n_live_tup, n_dead_tup, last_autovacuum, autovacuum_count
                                     from pg_stat_user_tables where relname = 'tracking_events'"
MD
chown postgres:postgres /var/lib/postgresql/README.md
