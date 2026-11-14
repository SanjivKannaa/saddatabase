# sadDatabase MySQL story base: up to three mysqld "nodes" in one box (ports 3306-3308), tools for the story.
FROM mysql:8.4
RUN microdnf install -y procps-ng less nano vim-minimal shadow-utils util-linux jq python3 python3-pyyaml tar xz findutils numactl-libs libaio which \
 && microdnf clean all
RUN rm -f /etc/my.cnf && mkdir -p /srv/mysql /var/log/mysql /var/run/mysqld /home/player /etc/mysql/nodes /opt/sad /srv/app \
 && usermod -d /home/player -s /bin/bash mysql \
 && chown -R mysql:mysql /srv /var/log/mysql /var/run/mysqld /home/player /etc/mysql \
 && chmod 700 /opt/sad
# third-party tools for the story (bin/fetch-vendor downloads them, checksums pinned in vendor.sha256)
COPY vendor/ /opt/vendor/
RUN tar -xzf /opt/vendor/gh-ost-v1.1.11-linux-amd64.tar.gz -C /usr/local/bin gh-ost \
 && rpm -i --nodeps /opt/vendor/percona-orchestrator-3.2.6-24.el9.x86_64.rpm /opt/vendor/percona-orchestrator-client-3.2.6-24.el9.x86_64.rpm \
 && rm -f /opt/vendor/*.rpm /opt/vendor/gh-ost-*.tar.gz && chmod 755 /opt/vendor \
 && tar -xJf /opt/vendor/mysql-8.4.13-linux-glibc2.28-x86_64-minimal.tar.xz -C /usr/local/bin --strip-components=2 \
      mysql-8.4.13-linux-glibc2.28-x86_64-minimal/bin/mysqlbinlog \
 && gh-ost --version >/dev/null && test -x /usr/local/orchestrator/orchestrator && mysqlbinlog --version >/dev/null
COPY lib.sh /usr/local/lib/sad/lib.sh
COPY node.cnf.tmpl /usr/local/lib/sad/node.cnf.tmpl
COPY svc unit.env /usr/local/lib/sad/
COPY --from=common unitlib.sh /usr/local/lib/sad/unitlib.sh
COPY --from=common systemctl journalctl service sudo /usr/local/bin/
RUN chmod 755 /usr/local/lib/sad/svc /usr/local/bin/systemctl /usr/local/bin/journalctl /usr/local/bin/service /usr/local/bin/sudo \
 && mkdir -p /var/lib/sad/journal && chown mysql:mysql /var/lib/sad/journal
COPY orcctl /usr/local/bin/orcctl
COPY --from=common sad-entrypoint /usr/local/bin/sad-entrypoint
COPY motd /etc/motd
COPY bashrc /home/player/.bashrc
COPY bashrc /home/player/.bash_profile
RUN for n in 1 2 3; do printf '#!/bin/bash\n# node%s = 127.0.0.1:%s\nexec mysql -S /var/run/mysqld/node%s.sock "$@"\n' $n $((3305+n)) $n > /usr/local/bin/node$n; done \
 && chmod +x /usr/local/bin/node? /usr/local/bin/orcctl \
 && printf '[client]\nuser=root\npassword=lab-root-pw\nsocket=/var/run/mysqld/node1.sock\n' > /home/player/.my.cnf \
 && chown mysql:mysql /home/player/.my.cnf /home/player/.bashrc /home/player/.bash_profile && chmod 600 /home/player/.my.cnf
LABEL saddb.user=mysql saddb.home=/home/player saddb.mem=1g
WORKDIR /home/player
ENTRYPOINT ["/usr/local/bin/sad-entrypoint"]
