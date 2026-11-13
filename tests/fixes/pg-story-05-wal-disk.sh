node1 <<'SQL'
SELECT pg_drop_replication_slot('node3');
ALTER SYSTEM SET archive_command = 'test ! -f /srv/wal_archive/%f && cp %p /srv/wal_archive/%f';
ALTER SYSTEM SET max_slot_wal_keep_size = '1GB';
SELECT pg_reload_conf();
SQL
sleep 5
node1 -c 'CHECKPOINT'
