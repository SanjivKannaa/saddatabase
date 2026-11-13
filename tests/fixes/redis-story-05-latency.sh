export REDISCLI_AUTH=QB-Admin-2026
sed -i "s/rc KEYS 'qb:session:\*'/rc --scan --pattern 'qb:session:*'/" /srv/app/session-cleaner.sh
sed -i 's/rc DEL qb:menu:all/rc UNLINK qb:menu:all/' /srv/app/menu-refresh.sh
node1 --user admin CONFIG SET lazyfree-lazy-user-del yes
node1 --user admin CONFIG REWRITE
sleep 16
