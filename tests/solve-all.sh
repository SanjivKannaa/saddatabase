#!/bin/bash
# For every scenario (or the ones named): the grader must FAIL on a fresh box and PASS after tests/fixes/<slug>.sh,
# which runs as the box's player user.
cd "$(dirname "$0")/.."
label() { docker image inspect -f "{{index .Config.Labels \"saddb.$2\"}}" "saddb/$1:latest"; }
rc=0
for s in ${@:-$(ls scenarios)}; do
  [ -f tests/fixes/$s.sh ] || { echo "? $s: no tests/fixes/$s.sh"; rc=1; continue; }
  c=$(docker run -d --rm --init --network none --memory "$(label $s mem)" --pids-limit "$(label $s pids | grep -xE "[0-9]+" || echo 256)" "saddb/$s:latest")
  for i in $(seq 240); do docker exec "$c" test -f /run/sad-ready 2>/dev/null && break; sleep 0.5; done
  if out=$(docker exec "$c" /opt/sad/check.sh 2>&1); then echo "✗ $s: grader PASSED on the broken box"; rc=1
  else echo "  $s broken: $(echo "$out" | tail -1 | cut -c1-150)"; fi
  docker exec -i -u "$(label $s user)" -w "$(label $s home)" "$c" bash -l < tests/fixes/$s.sh >/dev/null 2>&1
  if out=$(docker exec "$c" /opt/sad/check.sh 2>&1); then echo "✓ $s fixed: $(echo "$out" | tail -1)"
  else echo "✗ $s still failing after fix: $out"; rc=1; fi
  docker rm -fv "$c" >/dev/null
done
exit $rc
