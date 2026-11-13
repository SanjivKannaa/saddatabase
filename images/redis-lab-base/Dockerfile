# sadDatabase Redis story base: several redis-server "nodes" (and sentinels) in one box.
# nodeN: /etc/redis/nodes/nodeN.conf, data /srv/redis/nodeN, log /var/log/redis/nodeN.log
# sentinelN: /etc/redis/sentinel/sentinelN.conf, log /var/log/redis/sentinelN.log
FROM redis:8
RUN apt-get update && apt-get install -y --no-install-recommends less nano vim-tiny procps jq \
 && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /srv/redis /var/log/redis /var/run/redis /home/player /etc/redis/nodes /etc/redis/sentinel /etc/sad /opt/sad /srv/app /backups \
 && usermod -d /home/player -s /bin/bash redis \
 && chown -R redis:redis /srv/redis /var/log/redis /var/run/redis /home/player /etc/redis /srv/app \
 && chmod 755 /etc/sad && chmod 700 /opt/sad
COPY lib.sh /usr/local/lib/sad/lib.sh
COPY dbctl /usr/local/bin/dbctl
COPY --from=common sad-entrypoint /usr/local/bin/sad-entrypoint
COPY motd /etc/motd
COPY bashrc /home/player/.bashrc
COPY bashrc /home/player/.bash_profile
RUN for n in 1 2 3; do printf '#!/bin/bash\n# node%s = 127.0.0.1:%s  (redis-cli; auth: export REDISCLI_AUTH or use --user/--pass)\nexec redis-cli -p %s "$@"\n' $n $((6378+n)) $((6378+n)) > /usr/local/bin/node$n; done \
 && chmod 755 /usr/local/bin/node? /usr/local/bin/dbctl \
 && chown redis:redis /home/player/.bashrc /home/player/.bash_profile
LABEL saddb.user=redis saddb.home=/home/player saddb.mem=768m
WORKDIR /home/player
ENTRYPOINT ["/usr/local/bin/sad-entrypoint"]
