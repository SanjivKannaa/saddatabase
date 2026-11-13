# sadDatabase MongoDB story base: up to three mongod "nodes" in one box (ports 27017-27019). MongoDB 7.0
# (8.0 refuses to start on this host kernel). nodeN: /etc/mongodb/nodes/nodeN.conf, data /srv/mongo/nodeN,
# log /var/log/mongodb/nodeN.log
FROM mongo:7.0
RUN apt-get update && apt-get install -y --no-install-recommends less nano vim-tiny procps jq \
 && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /srv/mongo /var/log/mongodb /var/run/mongodb /home/player /etc/mongodb/nodes /etc/sad /opt/sad /srv/app /backups \
 && usermod -d /home/player -s /bin/bash mongodb \
 && chown -R mongodb:mongodb /srv/mongo /var/log/mongodb /var/run/mongodb /home/player /etc/mongodb /srv/app \
 && chmod 755 /etc/sad && chmod 700 /opt/sad
COPY lib.sh /usr/local/lib/sad/lib.sh
COPY verdant.js /usr/local/lib/sad/verdant.js
COPY dbctl /usr/local/bin/dbctl
COPY --from=common sad-entrypoint /usr/local/bin/sad-entrypoint
COPY motd /etc/motd
COPY bashrc /home/player/.bashrc
COPY bashrc /home/player/.bash_profile
RUN for n in 1 2 3; do printf '#!/bin/bash\n# node%s = 127.0.0.1:%s  (mongosh; add -u USER -p PASS --authenticationDatabase admin once auth is on)\nexec mongosh --port %s "$@"\n' $n $((27016+n)) $((27016+n)) > /usr/local/bin/node$n; done \
 && chmod 755 /usr/local/bin/node? /usr/local/bin/dbctl \
 && chown mongodb:mongodb /home/player/.bashrc /home/player/.bash_profile
LABEL saddb.user=mongodb saddb.home=/home/player saddb.mem=1536m saddb.pids=768
WORKDIR /home/player
ENTRYPOINT ["/usr/local/bin/sad-entrypoint"]
