psql -qX -At -c "select pg_terminate_backend(pid) from pg_stat_activity where usename='metrics'" -c 'alter role metrics connection limit 5'
