cat > ~/deploy/compose.yaml <<'YAML'
services:
  mysql:
    image: mysql:8.4.13
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD_FILE: /run/secrets/mysql_root_password
      MYSQL_DATABASE: bookstore
    secrets: [mysql_root_password]
    ports: ["127.0.0.1:3306:3306"]
    volumes:
      - mysql-data:/var/lib/mysql
      - ./conf.d:/etc/mysql/conf.d:ro
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "127.0.0.1", "--silent"]
      interval: 10s
    mem_limit: 1g
volumes:
  mysql-data:
secrets:
  mysql_root_password:
    file: ./secrets/mysql_root_password
YAML
mkdir -p ~/deploy/secrets && head -c 24 /dev/urandom | base64 > ~/deploy/secrets/mysql_root_password && chmod 600 ~/deploy/secrets/mysql_root_password
sed -i '/bind-address/d' ~/deploy/conf.d/lumen.cnf
