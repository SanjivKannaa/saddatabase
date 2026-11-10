#!/bin/bash
. /usr/local/lib/sad/lib.sh
r ping 2>/dev/null | grep -q PONG || fail "Redis is not running"
[ "$(r config get appendonly | tail -1)" = "yes" ] || fail "appendonly is off; persistence must stay on"
n=$(r eval "return #redis.call('keys','key:*')" 0)
[ "$n" -ge 9900 ] || fail "only $n of 10000 keys survived; too much data lost"
pass "Redis is up with AOF on and $n of 10000 keys"
