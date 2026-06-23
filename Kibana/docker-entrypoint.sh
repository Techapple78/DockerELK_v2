#!/bin/sh

set -e

case "$1" in
  -*)
    set -- kibana "$@"
    ;;
esac

if [ "$1" = "kibana" ] && [ "$(id -u)" = "0" ]; then
  exec runuser -u kibana -- "$@"
fi

exec "$@"
