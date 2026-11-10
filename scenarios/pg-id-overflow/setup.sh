#!/bin/bash
set -euo pipefail
. /usr/local/lib/sad/lib.sh
pg_start
sql <<'SQL'
create database tracking;
\c tracking
create table events (id serial primary key, kind text not null, payload jsonb, at timestamptz default now());
create table event_tags (event_id int not null references events(id), tag text not null, primary key (event_id, tag));
-- ids were burned in big chunks by a batch loader that reserved ranges
insert into events (id, kind, payload)
  select 2147483647 - 300000 + g*3, (array['click','view','buy'])[1+g%3], jsonb_build_object('n', g)
  from generate_series(0, 99999) g;
insert into event_tags select id, 'imported' from events where id % 7 = 0;
select setval('events_id_seq', 2147483647);
vacuum analyze;
SQL
pg_stop
