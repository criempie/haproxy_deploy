#!/bin/sh

# HAProxy ожидает сертификат и приватный ключ в одном PEM-файле.
# Certbot хранит их отдельно, поэтому этот скрипт собирает пары из
# /etc/letsencrypt/live/* в /tmp/certs — каталог сертификатов HAProxy.

set -eu

mkdir -p /tmp/certs
found=0

for certdir in /etc/letsencrypt/live/*; do
    [ -d "$certdir" ] || continue
    [ -r "$certdir/fullchain.pem" ] || continue
    [ -r "$certdir/privkey.pem" ] || continue

    certname=${certdir##*/}
    cat "$certdir/fullchain.pem" "$certdir/privkey.pem" > "/tmp/certs/$certname.pem"
    found=1
done

if [ "$found" -eq 0 ]; then
    echo "Не найдены сертификаты Let's Encrypt" >&2
    exit 1
fi
