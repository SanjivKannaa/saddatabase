sed -i "/128MBB/d" $PGDATA/postgresql.auto.conf; chmod 700 $PGDATA; pg_ctl -D $PGDATA -l /var/log/postgresql/postgresql.log -w start
