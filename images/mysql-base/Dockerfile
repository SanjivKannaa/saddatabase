# sadDatabase MySQL 8.4 base. Data dir baked into the image at /srv/mysql (the official one is a volume).
FROM mysql:8.4
RUN microdnf install -y procps-ng less nano vim-minimal shadow-utils util-linux && microdnf clean all
COPY my.cnf /etc/my.cnf
RUN mkdir -p /srv/mysql /var/log/mysql /var/run/mysqld /home/player /etc/mysql/conf.d /opt/sad \
 && usermod -d /home/player -s /bin/bash mysql \
 && chown -R mysql:mysql /srv/mysql /var/log/mysql /var/run/mysqld /home/player /etc/mysql/conf.d /etc/my.cnf \
 && chmod 750 /srv/mysql && chmod 700 /opt/sad \
 && su mysql -c "mysqld --defaults-file=/etc/my.cnf --initialize-insecure" 2>/dev/null
COPY lib.sh /usr/local/lib/sad/lib.sh
COPY svc unit.env /usr/local/lib/sad/
COPY --from=common unitlib.sh /usr/local/lib/sad/unitlib.sh
COPY --from=common systemctl journalctl service sudo /usr/local/bin/
RUN chmod 755 /usr/local/lib/sad/svc /usr/local/bin/systemctl /usr/local/bin/journalctl /usr/local/bin/service /usr/local/bin/sudo \
 && mkdir -p /var/lib/sad/journal && chown mysql:mysql /var/lib/sad/journal
COPY --from=common sad-entrypoint /usr/local/bin/sad-entrypoint
COPY motd /etc/motd
COPY bashrc /home/player/.bashrc
COPY bashrc /home/player/.bash_profile
# root password for the player (a DBA has admin creds); the grader uses its own socket-auth account
RUN . /usr/local/lib/sad/lib.sh && db_start \
 && mysql -uroot -e "INSTALL PLUGIN auth_socket SONAME 'auth_socket.so'; \
      CREATE USER sadgrader@localhost IDENTIFIED WITH auth_socket AS 'root'; \
      GRANT ALL ON *.* TO sadgrader@localhost WITH GRANT OPTION; \
      ALTER USER root@localhost IDENTIFIED BY 'lab-root-pw';" \
 && printf '[client]\nuser=root\npassword=lab-root-pw\n' > /home/player/.my.cnf \
 && chown mysql:mysql /home/player/.my.cnf /home/player/.bashrc /home/player/.bash_profile && chmod 600 /home/player/.my.cnf \
 && db_stop
LABEL saddb.user=mysql saddb.home=/home/player saddb.mem=1g
WORKDIR /home/player
ENTRYPOINT ["/usr/local/bin/sad-entrypoint"]
