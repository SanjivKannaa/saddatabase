sed -i '/reject/d' $PGDATA/pg_hba.conf
psql -qX -c 'select pg_reload_conf()' -c "alter role app login valid until 'infinity'"
psql -qX -d billing -c 'grant select on accounts to app'
