# sadDatabase PostgreSQL story base: up to three postgres "nodes" in one box (ports 5432-5434),
# PostgreSQL 17 plus 16 binaries (for the upgrade chapter). Node N: data /srv/pg/nodeN, log /var/log/postgresql/nodeN.log
FROM postgres:17
RUN sed -i 's/ main 17$/ main 17 16/' /etc/apt/sources.list.d/pgdg.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends postgresql-16 less nano vim-tiny iproute2 procps jq \
 && rm -rf /var/lib/apt/lists/* \
 && /usr/lib/postgresql/16/bin/postgres --version
ENV PATH=/usr/lib/postgresql/17/bin:$PATH PGHOST=/var/run/postgresql
RUN mkdir -p /srv/pg /var/log/postgresql /var/run/postgresql /etc/sad /opt/sad /srv/app /backups \
 && chown postgres:postgres /srv/pg /var/log/postgresql /var/run/postgresql /srv/app \
 && chmod 755 /etc/sad && chmod 700 /opt/sad
COPY lib.sh /usr/local/lib/sad/lib.sh
COPY svc unit.env /usr/local/lib/sad/
COPY --from=common unitlib.sh /usr/local/lib/sad/unitlib.sh
COPY --from=common systemctl journalctl service sudo /usr/local/bin/
RUN chmod 755 /usr/local/lib/sad/svc /usr/local/bin/systemctl /usr/local/bin/journalctl /usr/local/bin/service /usr/local/bin/sudo \
 && mkdir -p /var/lib/sad/journal && chown postgres:postgres /var/lib/sad/journal
COPY --from=common sad-entrypoint /usr/local/bin/sad-entrypoint
COPY motd /etc/motd
COPY bashrc /var/lib/postgresql/.bashrc
COPY bashrc /var/lib/postgresql/.profile
RUN for n in 1 2 3; do printf '#!/bin/bash\n# node%s = 127.0.0.1:%s (superuser psql over the local socket)\nexec psql -X -p %s "$@"\n' $n $((5431+n)) $((5431+n)) > /usr/local/bin/node$n; done \
 && chmod 755 /usr/local/bin/node? \
 && chown postgres:postgres /var/lib/postgresql/.bashrc /var/lib/postgresql/.profile
LABEL saddb.user=postgres saddb.home=/var/lib/postgresql saddb.mem=1g
WORKDIR /var/lib/postgresql
ENTRYPOINT ["/usr/local/bin/sad-entrypoint"]
