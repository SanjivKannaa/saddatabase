#!/bin/bash
. /usr/local/lib/sad/lib.sh
port=$(sed -n 's/^DB_PORT=//p' /srv/app/db.env | tr -d ' "')
case $port in 3307) p=2; o=3 ;; 3308) p=3; o=2 ;; *) fail "the app still points at port ${port:-?}: set DB_PORT in /srv/app/db.env to the new primary" ;; esac
[ "$(nq $p 'select 1')" = 1 ] || fail "node$p (the app's new primary) is not running"
[ "$(nq $p "select gtid_subset('$(cat /opt/sad/node1.gtids)', @@gtid_executed)")" = 1 ] || fail "node$p is missing transactions node1 committed: promoting it lost $(( $(cat /opt/sad/node1.orders) - $(nq $p 'select count(*) from bookstore.orders where id <= (select max(id) from bookstore.orders)') )) or more orders. Promote the replica that has all of them."
[ "$(nq $p 'select @@super_read_only + @@read_only')" = 0 ] || fail "node$p is still read-only"
[ -z "$(rs $p Source_Host)" ] || fail "node$p still has replication configured (from port $(rs $p Source_Port)): a primary shouldn't follow a dead server (RESET REPLICA ALL)"
persisted_ro() {  # 0 if mysqld-auto.cnf persists read_only/super_read_only = ON anywhere in its JSON
  python3 - "$1" <<'PY'
import json, sys
try: d = json.load(open(sys.argv[1]))
except Exception: sys.exit(1)
def walk(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k in ("super_read_only", "read_only") and isinstance(v, dict) and str(v.get("Value", "")).upper() in ("ON", "1"):
                return True
            if walk(v): return True
    return False
sys.exit(0 if walk(d) else 1)
PY
}
persisted_ro /srv/mysql/node$p/mysqld-auto.cnf && fail "node$p is writable now but goes back to read-only on restart (SET PERSIST super_read_only = OFF)"
grep -qsE '^\s*super[_-]read[_-]only\s*=\s*(1|ON|on)' /etc/mysql/nodes/node$p.cnf && fail "node$p.cnf still sets super_read_only: it'd come back read-only after a restart"
[ "$(nq $o 'select 1')" = 1 ] || fail "node$o (the remaining replica) is not running"
[ "$(rs $o Source_Port)" = "$port" ] || fail "node$o replicates from port $(rs $o Source_Port), not from the new primary ($port)"
[ "$(rs $o Replica_IO_Running)" = Yes ] && [ "$(rs $o Replica_SQL_Running)" = Yes ] || fail "node$o's replication isn't running: $(rs $o Last_IO_Error)$(rs $o Last_SQL_Error)"
[ "$(rs $o Auto_Position)" = 1 ] || fail "node$o should use GTID auto-positioning"
gt=$(nq $p "select @@gtid_executed" | tr -d '\n')
[ "$(nq $o "select wait_for_executed_gtid_set('$gt', 20)")" = 0 ] || fail "node$o hasn't caught up with node$p"
recent=$(nq $p "select count(*) from bookstore.orders where created_at >= now() - interval 5 second")
[ "${recent:-0}" -ge 2 ] || fail "no new orders are arriving on node$p: is the app able to write there?"
pass "node$p is the primary with all of node1's orders, node$o follows it, and orders are flowing again ($recent in the last 5 s)"
