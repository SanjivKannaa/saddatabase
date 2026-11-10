#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
pg_start
sql <<'SQL'
create role web login password 'w3b';
create role metrics login password 'm3trics';
create database app owner web;
alter system set max_connections = 15;
alter system set superuser_reserved_connections = 3;
SQL
pg_stop
