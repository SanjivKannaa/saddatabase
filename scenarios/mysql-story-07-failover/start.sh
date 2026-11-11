#!/bin/bash
. /usr/local/lib/sad/lib.sh
node_start 2; node_start 3
# the app: every second, read /srv/app/db.env and try to place an order
nohup bash -c 'while :; do . /srv/app/db.env; mysql -h "$DB_HOST" -P "$DB_PORT" -u app -pApp-Lumen-2026 bookstore -e "INSERT INTO orders (customer_id, total, status, created_at) VALUES (1 + FLOOR(RAND()*2000), ROUND(5 + RAND()*80, 2), \"paid\", NOW())" >/dev/null 2>&1; sleep 1; done' >/dev/null 2>&1 &
