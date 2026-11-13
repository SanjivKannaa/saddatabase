#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
node_init 1 17 "max_wal_senders = 0      # Tomás: we don't use replication, save memory"
load_parcels 1 >/dev/null
# Tomás "cleaned up" pg_hba.conf: the replication lines are gone
sed -i '/replication/d' /srv/pg/node1/pg_hba.conf
node_stop 1
cat > /var/lib/postgresql/README.md <<'MD'
# Standby for production (Dana)

  primary    node1, 127.0.0.1:5432, /srv/pg/node1     live traffic: don't keep it down
  standby    node2, 127.0.0.1:5433, /srv/pg/node2     doesn't exist yet
  wanted     streaming, hot standby (readable), own replication role (SCRAM, TCP 127.0.0.1), replication slot
MD
chown postgres:postgres /var/lib/postgresql/README.md
