#!/bin/sh

set -e

case "$1" in
  -*)
    set -- logstash "$@"
    ;;
esac

if [ "$1" = "logstash" ] && [ "$(id -u)" = "0" ]; then
  exec runuser -u logstash -- "$@"
fi

exec "$@"
