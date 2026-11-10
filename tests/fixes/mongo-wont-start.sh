sed -i 's|^\tport|  port|; s|dbPath: /srv/mongodb|dbPath: /srv/mongo|' /etc/mongodb/mongod.conf; dbctl start
