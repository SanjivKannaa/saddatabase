#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
db_start
redis-cli eval "for i=1,50000 do redis.call('SET','cache:product:'..i, '{\"id\":'..i..',\"name\":\"product '..i..'\",\"desc\":\"'..string.rep('lorem ipsum ', 70)..'\"}') end return 1" 0 >/dev/null
redis-cli eval "for i=1,500 do redis.call('SET','session:'..i, 'user-'..i, 'EX', 315360000) end return 1" 0 >/dev/null
redis-cli config set maxmemory 40mb >/dev/null
redis-cli config rewrite >/dev/null
redis-cli save >/dev/null
db_stop
