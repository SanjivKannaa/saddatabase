#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
db_start
redis-cli eval "for i=1,3000 do redis.call('SET','session:'..i, 'user-'..i..':'..string.rep('t', 60)) end
  for i=1,200000 do redis.call('RPUSH','queue:emails', 'mail-'..i) end
  for i=1,1500 do redis.call('HSET','user:avatars', 'u'..i, string.rep('iVBORw0KGgo', 360)) end
  redis.call('SET','report:2026:q3', string.rep('csv,', 600000))
  for i=1,200 do redis.call('SADD','tags:all', 'tag-'..i) end return 1" 0 >/dev/null
redis-cli save >/dev/null
db_stop
