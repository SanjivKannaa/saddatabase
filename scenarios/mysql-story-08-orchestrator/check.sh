#!/bin/bash
. /usr/local/lib/sad/lib.sh
API=http://127.0.0.1:3000/api
dbport() { sed -n 's/^DB_PORT=//p' /srv/app/db.env | tr -d ' "'; }
revive() {   # nothing was promoted: bring node1 back so the player can try again
  rm -f /etc/mysql/nodes/node1.dead /opt/sad/killed; node_start 1
}
if [ ! -f /opt/sad/killed ]; then
  curl -sf $API/health >/dev/null || fail "orchestrator isn't answering on 127.0.0.1:3000 (orcctl start; orcctl log)"
  [ "$(curl -s $API/check-global-recoveries | jq -r '.Details // .Message // .' 2>/dev/null)" != disabled ] || fail "global recoveries are disabled in orchestrator"
  n=$(curl -s "$API/cluster/127.0.0.1:3306" | jq 'length' 2>/dev/null)
  [ "${n:-0}" -ge 3 ] || fail "orchestrator sees ${n:-0} instance(s) in node1's cluster, not 3 (orchestrator-client -c topology -i 127.0.0.1:3306)"
  bad=$(curl -s "$API/cluster/127.0.0.1:3306" | jq -r '.[] | select(.IsLastCheckValid != true) | .Key.Port' 2>/dev/null)
  [ -z "$bad" ] || fail "orchestrator can't currently check instance(s) on port(s) $bad"
  [ "$(dbport)" = 3306 ] || fail "set DB_PORT back to 3306 (node1) before the drill"
  echo "orchestrator sees all 3 nodes. Pulling the plug on node1 now..."
  date +%s > /opt/sad/killed
  echo "pulled for the failover drill (sadDatabase grader)" > /etc/mysql/nodes/node1.dead
  node_kill 1
  for i in $(seq 60); do [ "$(dbport)" != 3306 ] && break; sleep 1; done
  if [ "$(dbport)" = 3306 ]; then
    promoted=""
    for n in 2 3; do [ "$(nq $n 'select @@read_only')" = 0 ] && promoted=$n; done
    if [ -z "$promoted" ]; then revive; fail "no failover within 60 s: nothing was promoted. node1 is back so you can try again (orcctl log shows why)"; fi
    fail "orchestrator promoted node$promoted, but the app still points at 3306: your hook didn't run or didn't work (orcctl log). Fix it, point the app at node$promoted, and Check again"
  fi
  echo "failover done after $(( $(date +%s) - $(cat /opt/sad/killed) ))s"
fi
port=$(dbport)
case $port in 3307) p=2; o=3 ;; 3308) p=3; o=2 ;; *) fail "the app points at port ${port:-?}, which isn't a surviving node" ;; esac
[ "$(nq $p 'select @@read_only + @@super_read_only')" = 0 ] || fail "node$p (the app's new primary) is read-only"
[ "$(rs $o Source_Port)" = "$port" ] || fail "node$o doesn't replicate from the new primary (port $port)"
[ "$(rs $o Replica_IO_Running)" = Yes ] && [ "$(rs $o Replica_SQL_Running)" = Yes ] || fail "node$o's replication isn't running"
rec=$(curl -s "$API/audit-recovery" | jq '[.[] | select(.IsSuccessful == true and (.AnalysisEntry.Analysis // "" | test("DeadMaster")))] | length' 2>/dev/null)
[ "${rec:-0}" -ge 1 ] || fail "orchestrator has no successful DeadMaster recovery on record: the failover has to be orchestrator's work"
sleep 3
recent=$(nq $p "select count(*) from bookstore.orders where created_at >= now() - interval 5 second")
[ "${recent:-0}" -ge 2 ] || fail "orders aren't arriving on node$p"
pass "orchestrator promoted node$p, re-homed node$o and ran your hook: the app moved to $port and orders kept flowing ($recent in the last 5 s)"
