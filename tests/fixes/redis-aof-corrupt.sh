echo y | redis-check-aof --fix /srv/redis/appendonlydir/appendonly.aof.manifest; dbctl start
