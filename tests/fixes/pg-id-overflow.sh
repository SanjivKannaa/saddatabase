psql -qX -d tracking -c "alter table events alter column id type bigint" -c "alter sequence events_id_seq as bigint" -c "alter table event_tags alter column event_id type bigint"
