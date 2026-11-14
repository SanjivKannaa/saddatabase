echo y | redis-check-aof --fix /srv/redis/appendonlydir/appendonly.aof.manifest; sudo systemctl start redis-server
