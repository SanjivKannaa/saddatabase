# Shared by systemctl / journalctl / service in sadDatabase boxes.
# unit.env (per base image) sets:
#   UNIT     unit name (postgresql, mysql, mongod, redis-server)
#   ALIASES  other accepted names (space separated)
#   MULTI    1 = several nodes in the box: units are UNIT@nodeN, and UNIT alone means every node
#   DESC     description; %i is replaced by the node name
#   PROC     the server's process name (fallback for "Main PID")
#   SUNIT / SDESC   (redis lab) sentinel units: SUNIT@sentinelN
. /usr/local/lib/sad/unit.env
SVC=/usr/local/lib/sad/svc
JDIR=/var/lib/sad/journal
HOST=$(cat /etc/hostname 2>/dev/null || echo localhost)

svc() {   # svc ACTION ITEM
  if [ "$MULTI" = 1 ]; then "$SVC" "$1" "$2"; else "$SVC" "$1"; fi
}
all_items() { if [ "$MULTI" = 1 ]; then "$SVC" items 2>/dev/null; else echo main; fi; }
is_sentinel() { [[ $1 == sentinel* ]]; }
unit_of() {
  if [ "$MULTI" != 1 ]; then echo "$UNIT"
  elif is_sentinel "$1"; then echo "$SUNIT@$1"
  else echo "$UNIT@$1"; fi
}
template_of() {
  if [ "$MULTI" != 1 ]; then echo "$UNIT"
  elif is_sentinel "$1"; then echo "$SUNIT@"
  else echo "$UNIT@"; fi
}
desc_of() {
  local d=$DESC; is_sentinel "$1" && d=$SDESC
  echo "${d//%i/$1}"
}
all_unit_names() {
  local i; if [ "$MULTI" = 1 ]; then echo "$UNIT"; [ -n "$SUNIT" ] && echo "$SUNIT"; fi
  for i in $(all_items); do unit_of "$i"; done | awk '!seen[$0]++'
}
name_is() {   # name_is NAME BASE: NAME is BASE or one of its aliases
  local a; [ "$1" = "$2" ] && return 0
  [ "$2" = "$UNIT" ] || return 1
  for a in $ALIASES; do [ "$1" = "$a" ] && return 0; done; return 1
}

# resolve NAME: print the items it means (may be none, e.g. "postgresql" before any cluster exists); 1 = unknown unit
resolve() {
  local a=${1%.service} base inst i u found=0
  if [[ $a == *[\*\?\[]* ]]; then   # glob, e.g. 'postgresql@*'
    for i in $(all_items); do u=$(unit_of "$i"); [[ $u == $a || $u.service == $1 ]] && { echo "$i"; found=1; }; done
    return 0
  fi
  if [ "$MULTI" != 1 ]; then
    base=${a%%@*}
    if name_is "$a" "$UNIT" || { [[ $a == *@* ]] && name_is "$base" "$UNIT"; }; then echo main; return 0; fi
    return 1
  fi
  if [[ $a != *@* ]]; then
    if name_is "$a" "$UNIT"; then all_items | grep -v '^sentinel'; return 0; fi
    if [ -n "$SUNIT" ] && [ "$a" = "$SUNIT" ]; then all_items | grep '^sentinel'; return 0; fi
    return 1
  fi
  base=${a%%@*}; inst=${a#*@}
  if [ -n "$SUNIT" ] && [ "$base" = "$SUNIT" ]; then
    [[ $inst =~ ^[0-9]+$ ]] && inst=sentinel$inst
    [[ $inst =~ ^sentinel[0-9]+$ ]] && { echo "$inst"; return 0; }; return 1
  fi
  name_is "$base" "$UNIT" || return 1
  [[ $inst =~ ^[0-9]+$ ]] && inst=node$inst
  [[ $inst =~ ^node[0-9]+$ ]] && { echo "$inst"; return 0; }
  return 1
}

# state_of ITEM: sets STATE (active|failed|inactive), PID and DEAD (why a node can't run, if it can't)
state_of() {
  PID=$(svc pid "$1" 2>/dev/null | head -1); DEAD=""
  if [ -n "$PID" ]; then STATE=active; return; fi
  DEAD=$(svc status "$1" 2>/dev/null | sed -n 's/.*: DOWN (\(.*\))$/\1/p' | head -1)
  if [ -n "$DEAD" ] || [ -f "$JDIR/$1.failed" ]; then STATE=failed; else STATE=inactive; fi
}

color() { if [ -t 1 ]; then printf '\033[%sm%s\033[0m' "$1" "$2"; else printf '%s' "$2"; fi; }
fmt_time() { [ -n "$1" ] && date -d "@$1" '+%a %Y-%m-%d %H:%M:%S %Z'; }
ago() {
  local s=$1 h m
  h=$((s / 3600)); m=$((s % 3600 / 60)); s=$((s % 60))
  if [ $h -gt 0 ]; then echo "${h}h ${m}min ago"; elif [ $m -gt 0 ]; then echo "${m}min ${s}s ago"; else echo "${s}s ago"; fi
}
started_at() {   # "Sat 2026-11-14 10:00:01 UTC; 3min 2s ago"
  local et; et=$(ps -o etimes= -p "$1" 2>/dev/null | tr -d ' ')
  [ -n "$et" ] || { [ -r "/proc/$1" ] && et=$(( $(date +%s) - $(stat -c %Y "/proc/$1") )); }
  [ -n "$et" ] && echo "$(fmt_time $(( $(date +%s) - et ))); $(ago "$et")"
}

jstamp() { date '+%b %d %H:%M:%S'; }
jlog() { mkdir -p "$JDIR" 2>/dev/null; echo "$(jstamp) $HOST $2" >> "$JDIR/$1.log" 2>/dev/null; }
jout() {   # the backend's output, as lines from the server process
  local l; [ -n "$2" ] || return 0
  while IFS= read -r l; do [ -n "$l" ] && jlog "$1" "$PROC[$$]: $l"; done <<< "$2"
}
jread() { cat "$JDIR/$1.log" 2>/dev/null; }
