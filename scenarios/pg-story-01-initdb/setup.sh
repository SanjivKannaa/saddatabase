#!/bin/bash
set -euo pipefail
cat > /var/lib/postgresql/README.md <<'MD'
# pg-01.parcelpoint (new) -- from Dana

Empty box, PostgreSQL 17 installed (initdb, pg_ctl, psql in PATH). Build the cluster like this:

  data dir      /srv/pg/node1            (dbctl start|stop|status node1 runs it)
  port          5432, listen on localhost only
  memory        shared_buffers = 256MB
  integrity     data checksums ON
  auth          no trust, no clear-text password. postgres logs in over the local socket (peer).
  database      parcels (UTF8), owner: parcels_owner (a role nobody logs in as)
  app login     parcels_app / Parcel-App-2026 (SCRAM), over TCP 127.0.0.1
                must be able to CREATE TABLE in schema "app" of parcels. Not superuser, not owner.

Tomás's app config already uses: host=127.0.0.1 port=5432 dbname=parcels user=parcels_app
MD
chown postgres:postgres /var/lib/postgresql/README.md
