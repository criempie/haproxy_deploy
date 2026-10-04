#!/bin/sh
set -eu

exec haproxy -f /usr/local/etc/haproxy/haproxy.cfg -W -db
