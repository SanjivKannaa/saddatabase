export REDISCLI_AUTH=QB-Admin-2026
node1 --user admin ACL SETUSER replica on '>QB-Repl-2026' '+psync' '+replconf' '+ping'
node1 --user admin CONFIG REWRITE
node2 --user admin CONFIG SET masteruser replica
node2 --user admin CONFIG SET masterauth QB-Repl-2026
node2 --user admin CONFIG SET replica-read-only yes
node2 --user admin REPLICAOF 127.0.0.1 6379
node2 --user admin CONFIG REWRITE
sleep 2
