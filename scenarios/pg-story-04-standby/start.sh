#!/bin/bash
. /usr/local/lib/sad/lib.sh
node_start 1
cat > /opt/sad/app.sql <<'SQL'
WITH s AS (INSERT INTO shipments (customer_id, tracking_no, status, weight_g)
           VALUES (1 + floor(random()*2000)::int, 'PL' || floor(random()*1e12)::text, 'label_created', 100 + floor(random()*5000)::int) RETURNING id)
INSERT INTO tracking_events (shipment_id, event) SELECT id, 'label_created' FROM s;
SQL
# the app: a new shipment twice a second (root process: the player can stop the server, not this)
nohup bash -c 'while :; do PGPASSWORD=Parcel-App-2026 psql -X -q -h 127.0.0.1 -p 5432 -U parcels_app -d parcels -f /opt/sad/app.sql >/dev/null 2>&1; sleep 0.5; done' >/dev/null 2>&1 &
