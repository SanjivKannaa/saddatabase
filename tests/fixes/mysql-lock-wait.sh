pid=$(mysql -N -e "select blocking_pid from sys.innodb_lock_waits limit 1")
[ -z "$pid" ] && pid=$(mysql -N -e "select trx_mysql_thread_id from information_schema.innodb_trx order by trx_started limit 1")
mysql -e "KILL $pid; SET PERSIST wait_timeout = 600; SET PERSIST interactive_timeout = 600;"
