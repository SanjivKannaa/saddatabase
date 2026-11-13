#!/bin/bash
. /usr/local/lib/sad/lib.sh
node_start 1; node_start 2; node_start 3
for i in $(seq 40); do [ "$(nq 1 "select sync_state from pg_stat_replication where application_name = 'node2'")" = sync ] && break; sleep 0.5; done
: > /opt/sad/committed
cat > /opt/sad/app.sql <<'SQL'
INSERT INTO shipments (customer_id, tracking_no, status, weight_g)
VALUES (1 + floor(random()*2000)::int, 'PD' || floor(random()*1e12)::text, 'delivered', 100 + floor(random()*5000)::int) RETURNING tracking_no;
SQL
# the drivers' app: saves a delivery every 0.3 s on DB_PORT; /opt/sad/committed lists the ones it was told were saved
nohup bash -c 'while :; do . /srv/app/db.env 2>/dev/null
  tn=$(PGPASSWORD=Parcel-App-2026 PGCONNECT_TIMEOUT=2 timeout 8 psql -X -q -At -h 127.0.0.1 -p "${DB_PORT:-5432}" -U parcels_app -d parcels -f /opt/sad/app.sql 2>/dev/null) \
    && [ -n "$tn" ] && echo "$tn" >> /opt/sad/committed
  sleep 0.3; done' >/dev/null 2>&1 &
# 03:12 node1's host dies; it comes back a little after someone has been promoted
nohup bash -c '. /usr/local/lib/sad/lib.sh
  sleep 4
  echo "host offline (power supply failure). Inês is on her way." > /etc/sad/node1.dead
  node_kill 1
  mv /srv/pg/node1 /opt/sad/node1.offline
  while :; do
    for p in 5433 5434; do [ "$(runuser -u postgres -- psql -X -At -p $p -d postgres -c "select pg_is_in_recovery()" 2>/dev/null)" = f ] && break 2; done
    sleep 2
  done
  sleep 15
  mv /opt/sad/node1.offline /srv/pg/node1 && chown -R postgres:postgres /srv/pg/node1
  rm -f /etc/sad/node1.dead /srv/pg/node1/postmaster.pid
  cat > /var/lib/postgresql/INES-node1-is-back.md <<MD
# $(date +%H:%M) node1 is back (Inês)

New power supply, the host is up. PostgreSQL on node1 is NOT started (/srv/pg/node1, port 5432).
It crashed while it was the primary. Please make it a standby of the new primary.
Do not let it come up as a primary: the app must never write there again.
MD
  chown postgres:postgres /var/lib/postgresql/INES-node1-is-back.md' >/dev/null 2>&1 &
