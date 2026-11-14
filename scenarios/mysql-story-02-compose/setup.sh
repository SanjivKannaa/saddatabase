#!/bin/bash
set -euo pipefail
mkdir -p /home/player/deploy/conf.d
cat > /home/player/deploy/compose.yaml <<'YAML'
# staging mysql -- marco
services:
  db:
    image: mysql:latest
    environment:
      MYSQL_ROOT_PASSWORD: hunter2
      MYSQL_DATABASE: bookstore
    ports:
      - "3306:3306"
    volumes:
      - ./conf.d:/etc/mysql/conf.d
YAML
cat > /home/player/deploy/conf.d/lumen.cnf <<'CNF'
[mysqld]
# security!! only local connections -- marco
bind-address            = 127.0.0.1
innodb_buffer_pool_size = 512M
max_connections         = 200
CNF
cp /opt/sad/check_compose.py /opt/sad/check_compose.py 2>/dev/null || true
chown -R mysql:mysql /home/player/deploy
rm -f /usr/local/bin/node1 /usr/local/bin/node2 /usr/local/bin/node3
cat > /etc/motd <<'MOTD'

 sadDatabase · Lumen Books · staging review
 ──────────────────────────────────────────
 you     mysql (OS user; sudo: systemctl only)
 review  ~/deploy/compose.yaml
         ~/deploy/conf.d/lumen.cnf
 note    no Docker daemon here: Check reviews
         the YAML (python3 + yaml are installed)
MOTD
