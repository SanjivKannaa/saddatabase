# Generic scenario image: build context is one scenarios/<slug>/ directory.
ARG BASE=saddb/pg-base:17
FROM ${BASE}
COPY . /opt/sad/
RUN rm -f /opt/sad/scenario.toml \
 && chown -R root:root /opt/sad && chmod -R go-rwx /opt/sad && chmod 700 /opt/sad/*.sh \
 && /opt/sad/setup.sh && rm -f /opt/sad/setup.sh
