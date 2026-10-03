#!/bin/sh
set -eu

/bin/sh /usr/local/bin/haproxy-scripts/prepare-certs.sh

exec haproxy -f /usr/local/etc/haproxy/haproxy.cfg -W -db
