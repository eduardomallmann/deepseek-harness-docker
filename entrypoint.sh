#!/bin/sh
set -eu

# Any arguments replace the default web launch, e.g. `docker run ... dsh --help`.
if [ "$#" -gt 0 ]; then
    exec "$@"
fi

# First start on an empty volume: seed the web profile with the bundled plugins.
profile="${DSH_HOME:-/data/.dsh}/profiles/web"
if [ ! -e "$profile/package.json" ] && [ -d /opt/dsh-seed/profiles/web ]; then
    mkdir -p "$profile"
    cp -a /opt/dsh-seed/profiles/web/. "$profile/"
fi

port="${DSH_PORT:-3080}"

if [ -n "${DSH_HOST:-}" ]; then
    # Native bind: dsh >= 0.2.1 accepts one concrete local address (never a wildcard).
    set -- dsh --profile web --no-open --host "$DSH_HOST" --port "$port"
else
    # Releases up to 0.2.0 only bind loopback, so dsh stays on 127.0.0.1 and a plain
    # TCP relay exposes it on the container's own address. dsh itself is not patched.
    internal_port="${DSH_INTERNAL_PORT:-3079}"
    container_ip="$(hostname -i | awk '{print $1}')"
    socat "TCP4-LISTEN:${port},bind=${container_ip},fork,reuseaddr" "TCP4:127.0.0.1:${internal_port}" &
    set -- dsh --profile web --no-open --host 127.0.0.1 --port "$internal_port"
fi

# Only understood by dsh >= 0.2.1; leave unset on older releases.
if [ -n "${DSH_PUBLIC_URL:-}" ]; then
    set -- "$@" --public-url "$DSH_PUBLIC_URL"
fi

# Comma-separated authorities (host or host:port) the browser may use to reach dsh.
old_ifs="$IFS"
IFS=,
for trusted in ${DSH_TRUSTED_HOSTS:-}; do
    [ -n "$trusted" ] && set -- "$@" --trusted-host "$trusted"
done
IFS="$old_ifs"

exec "$@"
