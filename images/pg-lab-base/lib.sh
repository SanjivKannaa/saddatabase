# Helpers for PostgreSQL story setup/start/check scripts (run as root).
# node_init N [version] [extra postgresql.conf lines...]   initdb nodeN (port 5431+N, checksums, C.UTF-8) and start it (NODE_LOCALE=... overrides the locale)
# node_start N | node_stop N | node_kill N
# ns N [psql args] <<SQL ... SQL     superuser psql on nodeN
# nq N "select ..." [db]             one value from nodeN
export PGHOST=/var/run/postgresql
nport() { echo $((5431 + $1)); }
node_init() {
  local n=$1 v=${2:-17}; shift; [ $# -gt 0 ] && shift
  runuser -u postgres -- /usr/lib/postgresql/$v/bin/initdb -D /srv/pg/node$n --data-checksums -E UTF8 --locale="${NODE_LOCALE:-C.UTF-8}" \
    --auth-local=peer --auth-host=scram-sha-256 >/dev/null
  { echo "# --- magickite lab settings ---"
    echo "port = $(nport $n)"
    echo "listen_addresses = 'localhost'"
    echo "cluster_name = 'node$n'"
    echo "shared_buffers = 64MB"
    echo "max_connections = 50"
    echo "log_line_prefix = '%m [%p] %q%u@%d '"
    for l in "$@"; do echo "$l"; done; } >> /srv/pg/node$n/postgresql.conf
  node_start $n
}
# Slot directories baked into an image layer can't be renamed on overlayfs (dropping the slot fails with EXDEV),
# so before a stopped node starts, re-create them in the container's writable layer.
node_start() {
  local d=/srv/pg/node$1 s
  if [ ! -f $d/postmaster.pid ]; then
    for s in $d/pg_replslot/*/; do [ -d "$s" ] || continue; s=${s%/}; cp -a "$s" "$s.unbake" && rm -rf "$s" && mv "$s.unbake" "$s"; done
  fi
  runuser -u postgres -- /usr/local/lib/sad/svc start node$1 >/dev/null
}
node_stop()  { runuser -u postgres -- /usr/local/lib/sad/svc stop node$1 >/dev/null; }
node_kill()  { local p; p=$(head -1 /srv/pg/node$1/postmaster.pid 2>/dev/null); [ -n "$p" ] && kill -9 "$p" 2>/dev/null; sleep 1; pkill -9 -f "cluster_name=node$1|postgres: node$1" 2>/dev/null; sleep 0.5; rm -f /var/run/postgresql/.s.PGSQL.$(nport $1)*; }
ns() { local n=$1; shift; runuser -u postgres -- psql -X -q -v ON_ERROR_STOP=1 -p "$(nport $n)" "$@"; }
nq() { runuser -u postgres -- psql -X -At -p "$(nport $1)" -d "${3:-postgres}" -c "$2" 2>/dev/null; }
db_start() { for d in /srv/pg/node?; do [ -f "$d/PG_VERSION" ] && node_start "${d##*node}"; done; }
db_stop()  { for d in /srv/pg/node?; do [ -f "$d/PG_VERSION" ] && node_stop "${d##*node}"; done; }
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
# load_parcels N : Parcelpoint's database on nodeN: roles parcels_app (pw Parcel-App-2026), db parcels with
# customers (2000), shipments (30000), tracking_events (90000). No FK from tracking_events (legacy).
load_parcels() {
  ns $1 <<'SQL'
CREATE ROLE parcels_app LOGIN PASSWORD 'Parcel-App-2026';
CREATE DATABASE parcels OWNER parcels_app;
\c parcels
SET ROLE parcels_app;
CREATE TABLE customers (id serial PRIMARY KEY, name text NOT NULL, email text NOT NULL, city text NOT NULL);
CREATE TABLE shipments (id bigserial PRIMARY KEY, customer_id int NOT NULL REFERENCES customers, tracking_no text NOT NULL UNIQUE,
  status text NOT NULL, weight_g int NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE tracking_events (id bigserial PRIMARY KEY, shipment_id bigint NOT NULL, event text NOT NULL, at timestamptz NOT NULL DEFAULT now());
INSERT INTO customers (name, email, city)
  SELECT 'Customer ' || i, 'c' || i || '@parcel.test', (ARRAY['Lisbon','Porto','Braga','Faro','Coimbra'])[1 + i % 5] FROM generate_series(1, 2000) i;
INSERT INTO shipments (customer_id, tracking_no, status, weight_g, created_at)
  SELECT 1 + (i * 7919) % 2000, 'PP' || lpad(i::text, 9, '0'), (ARRAY['delivered','delivered','delivered','in_transit','label_created'])[1 + i % 5],
         100 + (i * 37) % 20000, now() - make_interval(hours => (30000 - i) / 10) FROM generate_series(1, 30000) i;
INSERT INTO tracking_events (shipment_id, event, at)
  SELECT 1 + (i / 3), (ARRAY['picked_up','in_hub','out_for_delivery'])[1 + i % 3], now() - make_interval(mins => 90000 - i) FROM generate_series(0, 89999) i;
CREATE INDEX ON shipments (customer_id);
CREATE INDEX ON tracking_events (shipment_id);
RESET ROLE;
ANALYZE;
SQL
}
# a fingerprint of a table's contents: tsum N table [db]
tsum() { nq $1 "select count(*) || ':' || coalesce(md5(string_agg(t::text, '|' order by t::text)), '-') from $2 t" "${3:-parcels}"; }
