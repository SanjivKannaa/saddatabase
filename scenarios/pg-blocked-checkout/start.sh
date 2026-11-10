#!/bin/bash
. /usr/local/lib/sad/lib.sh
pg_start
# the forgotten report: updates A-100 inside a transaction and never commits
( echo "begin; update inventory set updated_at = now() where sku = 'A-100'; select 'report step 3 of 7';"; sleep infinity ) \
  | PGPASSWORD=r3port PGAPPNAME=nightly_report psql -X -q -h 127.0.0.1 -U reporting store >/dev/null 2>&1 &
sleep 1
# a checkout already stuck behind it
( echo "update inventory set qty = qty - 1 where sku = 'A-100';"; sleep infinity ) \
  | PGPASSWORD=sh0p PGAPPNAME=checkout-api psql -X -q -h 127.0.0.1 -U shop store >/dev/null 2>&1 &
sleep 0.5
