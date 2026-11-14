#!/bin/bash
. /usr/local/lib/sad/lib.sh
[ "$(nq 1 'select 1')" = 1 ] || fail "node1 (port 5432) isn't running: production is down"
[ "$(nq 1 'select pg_is_in_recovery()')" = f ] || fail "node1 is in recovery: it must stay the primary"
[ "$(nq 2 'select 1')" = 1 ] || fail "node2 (port 5433) isn't running"
[ "$(nq 2 'show data_directory')" = /srv/pg/node2 ] || fail "port 5433 is served from $(nq 2 'show data_directory'), not /srv/pg/node2"
[ "$(nq 2 'select pg_is_in_recovery()')" = t ] || fail "node2 isn't a standby (it's not in recovery): it was promoted, or standby.signal is missing"
IFS='|' read -r st sport slot user <<<"$(nq 2 "select status, sender_port, coalesce(slot_name, ''), substring(conninfo from 'user=([^ ]+)') from pg_stat_wal_receiver")"
[ "$st" = streaming ] || fail "node2 isn't streaming from node1 (WAL receiver: ${st:-none}). Look at /var/log/postgresql/node2.log"
[ "$sport" = 5432 ] || fail "node2 streams from port $sport, not node1 (5432)"
[ -n "$slot" ] || fail "node2 doesn't use a replication slot (primary_slot_name)"
[ "$(nq 1 "select slot_type || active from pg_replication_slots where slot_name = '$slot'")" = physicaltrue ] || fail "slot '$slot' isn't an active physical slot on node1"
ru=$(nq 1 "select usename from pg_stat_replication where state = 'streaming' and client_port is not null order by backend_start desc limit 1")
[ -n "$ru" ] || fail "node1 has no streaming replication connection over TCP"
[ "$ru" != postgres ] || fail "node2 replicates as postgres: use a dedicated replication role"
[ "$(nq 1 "select rolreplication::text || rolsuper::text from pg_roles where rolname = '$ru'")" = truefalse ] || fail "role $ru should have REPLICATION and not be a superuser"
[ "$(nq 1 "select auth_method from pg_hba_file_rules where 'replication' = any(database) and type like 'host%' and auth_method in ('trust','password') limit 1")" = "" ] || fail "node1's pg_hba.conf lets replication in with trust/password: use scram-sha-256"
probe="probe-$(date +%s%N)"
nq 1 "insert into customers (name, email, city) values ('$probe', 'grader@parcel.test', 'Braga')" parcels >/dev/null
for i in $(seq 20); do [ "$(nq 2 "select count(*) from customers where name = '$probe'" parcels)" = 1 ] && break; sleep 0.5; done
[ "$(nq 2 "select count(*) from customers where name = '$probe'" parcels)" = 1 ] || fail "a row written on node1 didn't reach node2 within 10 s"
runuser -u postgres -- /usr/local/lib/sad/svc restart node2 >/dev/null || fail "node2 doesn't come back after a restart"
for i in $(seq 20); do [ "$(nq 2 "select status from pg_stat_wal_receiver")" = streaming ] && break; sleep 0.5; done
[ "$(nq 2 'select pg_is_in_recovery()')" = t ] && [ "$(nq 2 "select status from pg_stat_wal_receiver")" = streaming ] || fail "after a restart node2 isn't a streaming standby any more: the standby config isn't persistent"
recent=$(nq 1 "select count(*) from shipments where created_at > now() - interval '5 seconds'" parcels)
[ "${recent:-0}" -ge 2 ] || fail "the app isn't writing to node1 (only $recent new shipments in 5 s)"
pass "node2 is a hot standby streaming from node1 as $ru through slot $slot, and survives a restart"
