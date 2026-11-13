#!/bin/bash
. /usr/local/lib/sad/lib.sh
node_start 1; node_start 3; node_start 2 || true
: > /opt/sad/ingest.log
# (restarted if mongosh exits, e.g. when no primary is reachable at first)
nohup bash -c 'while :; do mongosh --quiet "mongodb://verdant_app:Verdant-App-2026@127.0.0.1:27017,127.0.0.1:27018,127.0.0.1:27019/verdant?authSource=verdant&replicaSet=rs0&serverSelectionTimeoutMS=5000" \
  --file /opt/sad/ingest.js >/dev/null 2>&1; sleep 2; done' >/dev/null 2>&1 &
