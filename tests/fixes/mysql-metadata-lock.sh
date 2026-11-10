id=$(mysql -N -e 'select trx_mysql_thread_id from information_schema.innodb_trx order by trx_started limit 1')
mysql -e "kill $id"; sleep 2
