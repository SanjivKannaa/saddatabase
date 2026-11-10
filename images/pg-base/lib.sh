# Helpers for scenario setup/start/check scripts (run as root).
export PGDATA=/srv/pgdata
PGLOG=/var/log/postgresql/postgresql.log
pg_start() { su postgres -c "pg_ctl -D $PGDATA -l $PGLOG -w -t 60 start" >/dev/null; }
pg_stop()  { su postgres -c "pg_ctl -D $PGDATA -m fast -w stop" >/dev/null; }
# psql as the superuser over the local socket; extra args pass through (e.g. -d shop)
sql()      { su postgres -c "psql -X -q -v ON_ERROR_STOP=1 $*"; }
# one value, as superuser: q "select 1" [db]
q()        { su postgres -c "psql -X -At -d ${2:-postgres} -c \"$1\"" 2>/dev/null; }
pass()     { echo "PASS: $*"; }
fail()     { echo "FAIL: $*"; exit 1; }
