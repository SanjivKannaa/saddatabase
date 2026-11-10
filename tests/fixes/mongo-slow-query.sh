mongosh --quiet shop --eval "db.orders.createIndex({customerId: 1, status: 1, createdAt: -1})"
