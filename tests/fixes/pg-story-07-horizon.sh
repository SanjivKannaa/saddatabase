node1 <<'SQL'
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename = 'reporting' AND state LIKE 'idle in transaction%';
\c parcels
ROLLBACK PREPARED 'billing_migration_step3';
ALTER ROLE reporting SET idle_in_transaction_session_timeout = '15min';
ALTER SYSTEM SET max_prepared_transactions = 0;
SQL
dbctl restart node1
