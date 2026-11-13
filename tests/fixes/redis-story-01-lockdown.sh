node1 ACL SETUSER admin on '>QB-Admin-2026' '~*' '&*' '+@all'
node1 ACL SETUSER app on '>QB-App-2026' '~qb:*' '&qb:*' '+@all' '-@dangerous'
node1 CONFIG SET bind '127.0.0.1 -::1'
node1 CONFIG SET protected-mode yes
node1 ACL SETUSER default off
export REDISCLI_AUTH=QB-Admin-2026
node1 --user admin CONFIG REWRITE
