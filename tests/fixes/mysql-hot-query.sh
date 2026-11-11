mysql -e "SELECT query, exec_count, total_latency FROM sys.statement_analysis ORDER BY total_latency DESC LIMIT 3" shop
mysql -e "ALTER TABLE shop.orders ADD INDEX idx_coupon (coupon_code)"
