#!/bin/bash
. /usr/local/lib/sad/lib.sh
[ "$(nq 1 'select 1')" = 1 ] || fail "node1 (port 5432) isn't running"
[ "$(nq 1 'select pg_is_in_recovery()')" = f ] || fail "node1 should still be the primary"
[ "$(nq 2 'select 1')" = 1 ] || fail "node2 (port 5433) isn't running"
[ "$(nq 2 'select status from pg_stat_wal_receiver')" = streaming ] || fail "node2 isn't streaming from node1 any more"
[ "$(nq 1 "select active from pg_replication_slots where slot_name = 'node2'")" = t ] || fail "node2's slot is gone or inactive on node1: node2 needs it (don't drop the live standby's slot)"
dead=$(nq 1 "select string_agg(slot_name, ', ') from pg_replication_slots where not active")
[ -z "$dead" ] || fail "node1 still has inactive slot(s): $dead. Every WAL segment since their restart_lsn is kept"
mk=$(nq 1 "select setting from pg_settings where name = 'max_slot_wal_keep_size'")
[ "$mk" != -1 ] || fail "max_slot_wal_keep_size is -1 (unlimited): a forgotten slot can still fill the disk"
seg=$(nq 1 "select pg_walfile_name(pg_switch_wal())")
for i in $(seq 30); do [ "$(nq 1 'select last_archived_wal from pg_stat_archiver')" \> "$seg" ] || [ "$(nq 1 'select last_archived_wal from pg_stat_archiver')" = "$seg" ] && break; sleep 0.5; done
[ -f "/srv/wal_archive/$seg" ] || fail "WAL segment $seg wasn't archived to /srv/wal_archive within 15 s ($(nq 1 'select failed_count || $$ failures, last: $$ || coalesce(last_failed_wal, $$-$$) from pg_stat_archiver'))"
ready=$(ls /srv/pg/node1/pg_wal/archive_status/ 2>/dev/null | grep -c '\.ready$')
[ "$ready" -le 2 ] || fail "$ready WAL segments are still waiting to be archived"
nq 1 "checkpoint" >/dev/null; nq 1 "checkpoint" >/dev/null
mb=$(nq 1 "select (sum(size) / 1048576)::int from pg_ls_waldir()")
[ "${mb:-9999}" -lt 200 ] || fail "after a CHECKPOINT node1's pg_wal is still ${mb} MB (want < 200 MB): something still pins WAL"
pass "pg_wal is ${mb} MB after a checkpoint, archiving works, no dead slots, max_slot_wal_keep_size = ${mk} MB, node2 still streaming"
