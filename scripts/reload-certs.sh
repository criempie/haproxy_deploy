#!/bin/sh

# Скрипт для пересборки сертификатов с последующей мягкой перезагрузкой haproxy.
# Можно вызвать скрипт снаружи контейнера:
# docker compose exec -T haproxy /bin/sh /usr/local/bin/haproxy-scripts/reload-certs.sh

set -eu

/bin/sh /usr/local/bin/haproxy-scripts/prepare-certs.sh

# В master-worker режиме SIGUSR2 запускает мягкую перезагрузку HAProxy.
kill -USR2 1
