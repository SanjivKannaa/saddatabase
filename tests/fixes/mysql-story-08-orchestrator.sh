node1 -e "CREATE USER 'orc'@'127.0.0.1' IDENTIFIED BY 'Orc-Lumen-2026'; GRANT SUPER, PROCESS, REPLICATION SLAVE, REPLICATION CLIENT, RELOAD ON *.* TO 'orc'@'127.0.0.1'; GRANT SELECT ON mysql.slave_master_info TO 'orc'@'127.0.0.1';"
cat > /srv/orchestrator/orchestrator.conf.json <<'JSON'
{
  "ListenAddress": "127.0.0.1:3000",
  "MySQLTopologyUser": "orc",
  "MySQLTopologyPassword": "Orc-Lumen-2026",
  "BackendDB": "sqlite",
  "SQLite3DataFile": "/srv/orchestrator/orchestrator.sqlite3",
  "DiscoverByShowSlaveHosts": true,
  "HostnameResolveMethod": "none",
  "MySQLHostnameResolveMethod": "",
  "InstancePollSeconds": 1,
  "RecoverMasterClusterFilters": ["*"],
  "RecoverIntermediateMasterClusterFilters": ["*"],
  "ApplyMySQLPromotionAfterMasterFailover": true,
  "DelayMasterPromotionIfSQLThreadNotUpToDate": true,
  "PostMasterFailoverProcesses": ["sed -i 's/^DB_PORT=.*/DB_PORT={successorPort}/' /srv/app/db.env"]
}
JSON
orcctl start
export ORCHESTRATOR_API=http://127.0.0.1:3000/api
sleep 2; orchestrator-client -c discover -i 127.0.0.1:3306
for i in $(seq 30); do [ "$(orchestrator-client -c topology -i 127.0.0.1:3306 | wc -l)" -ge 3 ] && break; sleep 1; done
sleep 5
