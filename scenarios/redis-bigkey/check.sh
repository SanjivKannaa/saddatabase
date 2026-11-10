#!/bin/bash
. /usr/local/lib/sad/lib.sh
f=/home/player/solution
[ -s "$f" ] || fail "no answer found in ~/solution"
ans=$(tr -d '[:space:]"' < "$f")
r ping 2>/dev/null | grep -q PONG || fail "Redis is not running (it needs to be up to grade)"
want=$(r eval "local best, bk = -1, '' local cur = '0'
  repeat local res = redis.call('SCAN', cur, 'COUNT', 1000) cur = res[1]
    for _, k in ipairs(res[2]) do local m = redis.call('MEMORY', 'USAGE', k, 'SAMPLES', 0) if m > best then best, bk = m, k end end
  until cur == '0' return bk" 0)
[ "$ans" = "$want" ] && pass "$want is the biggest key by memory" || fail "'$ans' is not the key using the most memory"
