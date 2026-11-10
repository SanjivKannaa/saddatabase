#!/bin/bash
# Publish sadDatabase as https://sad.db.magickite on magickite. Run as the owner: sudo deploy/install-magickite.sh
# 1) reissue the nginx server cert (same key, same expiry 2027-12-05) with SAN sad.db.magickite
# 2) append the nginx vhost, test, reload   3) landing-page card   4) user service for magickite (needs linger: on)
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd); CA=/home/magickite/work/magickite-ca; ts=$(date +%Y%m%d-%H%M)
CONF=/etc/nginx/sites-available/magickite.conf; LANDING=/var/www/magickite/index.html

cp -p $CA/server.cnf $CA/server.cnf.bak-$ts; cp -p $CA/server.crt $CA/server.crt.bak-$ts
cp -p /etc/nginx/tls/magickite.crt /etc/nginx/tls/magickite.crt.bak-$ts; cp -p $CONF /root/magickite.conf.bak-$ts; cp -p $LANDING /root/index.html.bak-$ts
grep -q 'DNS:sad.db.magickite' $CA/server.cnf || sed -i 's/DNS:kafka.magickite,/DNS:kafka.magickite,DNS:sad.db.magickite,/' $CA/server.cnf
openssl req -new -key $CA/server.key -config $CA/server.cnf -out $CA/server.csr
openssl x509 -req -in $CA/server.csr -CA $CA/ca.crt -CAkey $CA/ca.key -CAserial $CA/ca.srl \
  -extfile $CA/server.cnf -extensions v3 -not_after 20271205064123Z -sha256 -out $CA/server.crt.new
openssl verify -CAfile $CA/ca.crt $CA/server.crt.new
mv $CA/server.crt.new $CA/server.crt; install -m 644 $CA/server.crt /etc/nginx/tls/magickite.crt

grep -q 'server_name sad.db.magickite' $CONF || cat "$HERE/nginx-sad.db.magickite.conf" >> $CONF
nginx -t && systemctl reload nginx

grep -q 'sad.db.magickite' $LANDING || sed -i '\#href="https://db-oncall.magickite/"#a <a class="card" href="https://sad.db.magickite/"><b>sadDatabase</b><span>Fix broken databases in a browser shell (DBA practice)</span></a>' $LANDING

install -o magickite -g magickite -m 644 -D "$HERE/saddatabase.service" /home/magickite/.config/systemd/user/saddatabase.service
echo "done (backups: *.bak-$ts). Now, as magickite (not sudo):"
echo "  pkill -f 'uvicorn app.main:app'; systemctl --user daemon-reload && systemctl --user enable --now saddatabase"
