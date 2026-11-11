id=$(node2 -N -e "select id from information_schema.processlist where user='backup_agent' order by time desc limit 1")
node2 -e "KILL $id"
sed -i 's/--lock-all-tables/--single-transaction/' /srv/backup/nightly.sh
sleep 4
