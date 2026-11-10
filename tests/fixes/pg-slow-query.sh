psql -qX -d shop -c "drop index orders_customer_id_idx" -c "create index on orders (customer_id, status, created_at desc)"
