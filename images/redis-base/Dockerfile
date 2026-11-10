# sadDatabase Redis 8 base. Data in /srv/redis, config /etc/redis/redis.conf (owned by the redis user).
FROM redis:8
RUN apt-get update && apt-get install -y --no-install-recommends less nano vim-tiny procps \
 && rm -rf /var/lib/apt/lists/*
COPY redis.conf /etc/redis/redis.conf
RUN mkdir -p /srv/redis /var/log/redis /var/run/redis /home/player /opt/sad \
 && usermod -d /home/player -s /bin/bash redis \
 && chown -R redis:redis /srv/redis /var/log/redis /var/run/redis /home/player /etc/redis \
 && chmod 700 /opt/sad
COPY lib.sh /usr/local/lib/sad/lib.sh
COPY dbctl /usr/local/bin/dbctl
COPY --from=common sad-entrypoint /usr/local/bin/sad-entrypoint
COPY motd /etc/motd
COPY bashrc /home/player/.bashrc
COPY bashrc /home/player/.bash_profile
RUN chown redis:redis /home/player/.bashrc /home/player/.bash_profile
LABEL saddb.user=redis saddb.home=/home/player saddb.mem=512m
WORKDIR /home/player
ENTRYPOINT ["/usr/local/bin/sad-entrypoint"]
