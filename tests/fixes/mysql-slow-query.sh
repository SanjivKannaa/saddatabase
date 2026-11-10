mysql shop -e "alter table orders modify customer_ref int unsigned not null, add index idx_cust_created (customer_ref, created_at)"
