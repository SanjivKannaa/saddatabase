#!/bin/bash
. /usr/local/lib/sad/lib.sh
node_start 1
# the BI tool: opens a REPEATABLE READ transaction for its "consistent dashboard" and never closes it
nohup bash -c '(echo "BEGIN ISOLATION LEVEL REPEATABLE READ;"; echo "SELECT count(*) FROM shipments;"; exec sleep infinity) \
  | PGPASSWORD=Report-Parcel-2026 PGAPPNAME=parcel-dashboard psql -X -q -h 127.0.0.1 -p 5432 -U reporting -d parcels >/dev/null 2>&1' >/dev/null 2>&1 &
sleep 1
# the app: tracking updates, all day long
nohup bash -c 'while :; do PGPASSWORD=Parcel-App-2026 psql -X -q -h 127.0.0.1 -p 5432 -U parcels_app -d parcels \
  -c "UPDATE tracking_events SET event = event WHERE id IN (SELECT 1 + floor(random() * 90000)::int FROM generate_series(1, 20))" >/dev/null 2>&1; sleep 0.5; done' >/dev/null 2>&1 &
