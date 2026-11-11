for id in $(mysql -N -e "select id from information_schema.processlist where user='reporting'"); do mysql -e "KILL $id"; done
mysql -e "ALTER USER 'reporting'@'localhost' WITH MAX_USER_CONNECTIONS 5"
