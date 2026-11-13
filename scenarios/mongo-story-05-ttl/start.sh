#!/bin/bash
. /usr/local/lib/sad/lib.sh
node_start 1
nohup bash -c 'while :; do runuser -u mongodb -- mongosh --quiet "mongodb://verdant_app:Verdant-App-2026@127.0.0.1:27017/verdant?authSource=verdant" --file /srv/app/ingest.js >/dev/null 2>&1; sleep 1; done' >/dev/null 2>&1 &
