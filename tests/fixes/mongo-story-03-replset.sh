openssl rand -base64 756 > /etc/mongodb/keyfile 2>/dev/null || head -c 756 /dev/urandom | base64 -w0 > /etc/mongodb/keyfile
chmod 400 /etc/mongodb/keyfile
sed -i '/^security:/a\  keyFile: /etc/mongodb/keyfile' /etc/mongodb/nodes/node1.conf
printf 'security:\n  keyFile: /etc/mongodb/keyfile\n' | tee -a /etc/mongodb/nodes/node2.conf >> /etc/mongodb/nodes/node3.conf
for n in 1 2 3; do printf 'replication:\n  replSetName: rs0\n' >> /etc/mongodb/nodes/node$n.conf; done
dbctl restart
mongosh 'mongodb://admin:Verdant-Admin-2026@127.0.0.1:27017/?authSource=admin&directConnection=true' --quiet --eval '
  rs.initiate({ _id: "rs0", members: [
    { _id: 0, host: "127.0.0.1:27017" }, { _id: 1, host: "127.0.0.1:27018" }, { _id: 2, host: "127.0.0.1:27019" } ] })'
sleep 15
