#!/bin/sh

# Мягко перезагружает HAProxy после экспорта новых PEM-файлов.
# Вызывается с хоста, например из hooks/after-renew.sh в certbot_deploy.

set -eu

# В master-worker режиме SIGUSR2 запускает мягкую перезагрузку HAProxy.
kill -USR2 1
