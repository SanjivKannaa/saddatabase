chmod 400 /etc/mongodb/keyfile-node2 && sudo systemctl start mongod@node2
A='mongodb://admin:Verdant-Admin-2026@127.0.0.1:27017,127.0.0.1:27018/admin?authSource=admin&replicaSet=rs0'
sleep 5
mongosh "$A" --quiet --eval 'rs.remove("127.0.0.1:27019")'
sudo systemctl stop mongod@node3 && rm -rf /srv/mongo/node3/* && sudo systemctl start mongod@node3
mongosh "$A" --quiet --eval 'rs.add("127.0.0.1:27019")'
mongosh "$A" --quiet --eval 'db.adminCommand({ setDefaultRWConcern: 1, defaultWriteConcern: { w: "majority" } })'
sleep 15
