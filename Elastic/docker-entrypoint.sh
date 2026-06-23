#!/bin/sh

set -e

case "$1" in
  -*)
    set -- elasticsearch "$@"
    ;;
esac

if [ "$1" = "elasticsearch" ] && [ "$(id -u)" = "0" ]; then
  chown -R elasticsearch:elasticsearch /usr/share/elasticsearch/data
  exec runuser -u elasticsearch -- "$@"
fi

exec "$@"
