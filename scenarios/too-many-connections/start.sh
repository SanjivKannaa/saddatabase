#!/bin/bash
. /usr/local/lib/sad/lib.sh
pg_start
for i in $(seq 1 14); do
  ( echo "select 1;"; sleep infinity ) \
    | PGPASSWORD=m3trics PGAPPNAME=metrics-collector psql -X -q -h 127.0.0.1 -U metrics app >/dev/null 2>&1 &
done
sleep 2
