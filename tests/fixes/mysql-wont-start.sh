sed -i "/query_cache/d; /log-error/d" /etc/mysql/conf.d/legacy-tuning.cnf; dbctl start
