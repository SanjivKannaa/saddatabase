#!/bin/bash
. /usr/local/lib/sad/lib.sh
[ "$(nq 1 'select 1')" = 1 ] || fail "node1 (port 5432) isn't running"
[ "$(nq 1 'show data_directory')" = /srv/pg/node1 ] || fail "port 5432 is served from $(nq 1 'show data_directory'): production is /srv/pg/node1"
[ "$(nq 1 'select pg_is_in_recovery()')" = f ] || fail "node1 is in recovery: it should be the writable production server"
[ "$(nq 1 'select timeline_id from pg_control_checkpoint()')" = 1 ] || fail "node1 is on a new timeline: production was replaced by a restored copy, losing everything after the DELETE"
ls /srv/wal_archive/*.history >/dev/null 2>&1 && fail "the production WAL archive now has a timeline history file ($(cd /srv/wal_archive && ls *.history | head -1)): a restored copy was promoted with archiving on"
want=$(cat /opt/sad/shipments.sum); got=$(tsum 1 shipments)
if [ "$got" != "$want" ]; then
  n=$(nq 1 'select count(*) from shipments' parcels)
  [ "${n:-0}" = 0 ] && fail "parcels.shipments is still empty"
  [ "${n}" -lt "${want%%:*}" ] && fail "shipments has $n rows, but had ${want%%:*} right before the DELETE: today's shipments are missing (a base backup alone only goes back to last night)"
  [ "${n}" -gt "${want%%:*}" ] && fail "shipments has $n rows, more than the ${want%%:*} it had before the DELETE: duplicates?"
  fail "shipments has the right number of rows ($n) but not the same contents as right before the DELETE (today's status changes?)"
fi
[ "$(tsum 1 tracking_events)" = "$(cat /opt/sad/tracking_events.sum)" ] || fail "tracking_events isn't as it was: the changes made after the DELETE must stay"
[ "$(tsum 1 customers)" = "$(cat /opt/sad/customers.sum)" ] || fail "customers isn't as it was: the changes made after the DELETE must stay"
pass "shipments is back exactly as it was before the DELETE; later changes kept; production and its archive untouched"
