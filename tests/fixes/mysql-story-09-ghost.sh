node1 -e "CREATE USER 'ghost'@'127.0.0.1' IDENTIFIED BY 'Ghost-Lumen-2026'; GRANT ALTER, CREATE, DELETE, DROP, INDEX, INSERT, LOCK TABLES, SELECT, TRIGGER, UPDATE ON bookstore.* TO 'ghost'@'127.0.0.1'; GRANT SUPER, REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO 'ghost'@'127.0.0.1'; GRANT SELECT ON performance_schema.* TO 'ghost'@'127.0.0.1';"
gh-ost --host=127.0.0.1 --port=3307 --user=ghost --password='Ghost-Lumen-2026' \
  --database=bookstore --table=books --alter="MODIFY isbn VARCHAR(17) NOT NULL, ADD INDEX idx_isbn (isbn)" \
  --chunk-size=2000 --max-load=Threads_running=25 --critical-load=Threads_running=500 \
  --initially-drop-ghost-table --ok-to-drop-table --exact-rowcount --cut-over-lock-timeout-seconds=2 --execute > /tmp/ghost.log 2>&1
echo "gh-ost exit $?"
