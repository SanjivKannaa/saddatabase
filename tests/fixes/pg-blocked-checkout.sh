psql -qX -At -c "select pg_terminate_backend(pid) from pg_stat_activity where application_name='nightly_report'" -c "alter role reporting set idle_in_transaction_session_timeout='60s'"
