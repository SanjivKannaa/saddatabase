node2 -e "SET sql_log_bin=0; DELETE FROM bookstore.orders WHERE id=900001; UPDATE bookstore.customers SET email='reader777@mail.test' WHERE id=777; SET sql_log_bin=1; START REPLICA;"
g1=$(node1 -N -e "select @@gtid_executed" | tr -d '\n')
u2=$(node2 -N -e "select @@server_uuid")
errant=$(node2 -N -e "select gtid_subtract(@@gtid_executed, '$g1')" | tr -d '\n')   # e.g. uuid:1-2
range=${errant#*:}; a=${range%-*}; b=${range#*-}
for n in $(seq $a $b); do node1 -e "SET GTID_NEXT='$u2:$n'; BEGIN; COMMIT; SET GTID_NEXT=AUTOMATIC;"; done
node2 -e "SET PERSIST super_read_only = ON"
sleep 2
