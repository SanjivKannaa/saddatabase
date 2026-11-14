# sadDatabase MongoDB 7.0 base (8.0 refuses to start on this host kernel). Data baked in at /srv/mongo.
FROM mongo:7.0
RUN apt-get update && apt-get install -y --no-install-recommends less nano vim-tiny procps \
 && rm -rf /var/lib/apt/lists/*
COPY mongod.conf /etc/mongodb/mongod.conf
RUN mkdir -p /srv/mongo /var/log/mongodb /var/run/mongodb /home/player /etc/mongodb /opt/sad \
 && usermod -d /home/player -s /bin/bash mongodb \
 && chown -R mongodb:mongodb /srv/mongo /var/log/mongodb /var/run/mongodb /home/player /etc/mongodb \
 && chmod 700 /opt/sad
COPY lib.sh /usr/local/lib/sad/lib.sh
COPY svc unit.env /usr/local/lib/sad/
COPY --from=common unitlib.sh /usr/local/lib/sad/unitlib.sh
COPY --from=common systemctl journalctl service sudo /usr/local/bin/
RUN chmod 755 /usr/local/lib/sad/svc /usr/local/bin/systemctl /usr/local/bin/journalctl /usr/local/bin/service /usr/local/bin/sudo \
 && mkdir -p /var/lib/sad/journal && chown mongodb:mongodb /var/lib/sad/journal
COPY --from=common sad-entrypoint /usr/local/bin/sad-entrypoint
COPY motd /etc/motd
COPY bashrc /home/player/.bashrc
COPY bashrc /home/player/.bash_profile
RUN chown mongodb:mongodb /home/player/.bashrc /home/player/.bash_profile
LABEL saddb.user=mongodb saddb.home=/home/player saddb.mem=768m
WORKDIR /home/player
ENTRYPOINT ["/usr/local/bin/sad-entrypoint"]
