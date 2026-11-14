# sadDatabase base image: PostgreSQL 17 with its data directory baked into the image
# (not a volume), so each scenario can pre-load data and break things at build time.
FROM postgres:17
RUN apt-get update \
 && apt-get install -y --no-install-recommends less nano vim-tiny iproute2 procps \
 && rm -rf /var/lib/apt/lists/*
ENV PGDATA=/srv/pgdata \
    PATH=/usr/lib/postgresql/17/bin:$PATH
RUN mkdir -p /srv/pgdata /var/log/postgresql /opt/sad \
 && chown postgres:postgres /srv/pgdata /var/log/postgresql \
 && chmod 700 /opt/sad \
 && su postgres -c "initdb -D /srv/pgdata --auth-local=peer --auth-host=scram-sha-256 -E UTF8 --locale=C.UTF-8" >/dev/null
COPY lib.sh /usr/local/lib/sad/lib.sh
COPY --from=common sad-entrypoint /usr/local/bin/sad-entrypoint
COPY svc unit.env /usr/local/lib/sad/
COPY --from=common unitlib.sh /usr/local/lib/sad/unitlib.sh
COPY --from=common systemctl journalctl service sudo /usr/local/bin/
RUN chmod 755 /usr/local/lib/sad/svc /usr/local/bin/systemctl /usr/local/bin/journalctl /usr/local/bin/service /usr/local/bin/sudo \
 && mkdir -p /var/lib/sad/journal && chown postgres:postgres /var/lib/sad/journal
COPY motd /etc/motd
COPY bashrc /var/lib/postgresql/.bashrc
COPY bashrc /var/lib/postgresql/.profile
RUN chown postgres:postgres /var/lib/postgresql/.bashrc /var/lib/postgresql/.profile
LABEL saddb.user=postgres saddb.home=/var/lib/postgresql saddb.mem=512m
WORKDIR /var/lib/postgresql
ENTRYPOINT ["/usr/local/bin/sad-entrypoint"]
