T=$(grep -m1 'DELETE FROM shipments' /var/log/postgresql/node1.log | awk '{print $1, $2, $3}')
mkdir -m 700 /srv/pg/node2
tar -xzf /backups/nightly/base.tar.gz -C /srv/pg/node2
tar -xzf /backups/nightly/pg_wal.tar.gz -C /srv/pg/node2/pg_wal
cat >> /srv/pg/node2/postgresql.auto.conf <<CONF
port = 5433
archive_mode = off
restore_command = 'cp /srv/wal_archive/%f %p'
recovery_target_time = '$T'
recovery_target_action = 'pause'
CONF
touch /srv/pg/node2/recovery.signal
sudo systemctl start postgresql@node2
for i in $(seq 60); do [ "$(node2 -Atc 'select pg_get_wal_replay_pause_state()')" = paused ] && break; sleep 0.5; done
node1 -d parcels -c 'TRUNCATE shipments'
pg_dump -p 5433 -d parcels -t shipments --data-only | psql -X -q -d parcels
sudo systemctl stop postgresql@node2
