need=$(node2 -e 'SHOW REPLICA STATUS\G' | sed -n 's/^ *Source_Log_File: //p')
node1 -e "PURGE BINARY LOGS TO '$need'; SET PERSIST binlog_expire_logs_seconds = 604800;"
