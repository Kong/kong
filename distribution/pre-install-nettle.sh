#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

source .requirements

function main() {
    echo '--- installing nettle ---'

    curl -fsSLo /tmp/nettle-${KONG_DEP_NETTLE_VERSION}.tar.gz https://ftp.gnu.org/gnu/nettle/nettle-${KONG_DEP_NETTLE_VERSION}.tar.gz
    cd /tmp
    tar xzf nettle-${KONG_DEP_NETTLE_VERSION}.tar.gz
    ln -s /tmp/nettle-${KONG_DEP_NETTLE_VERSION} /tmp/nettle
    cd /tmp/nettle

    # shellcheck disable=SC2034
    LDFLAGS="-Wl,-rpath,/usr/local/kong/lib"

    ./configure --disable-static \
        --libdir=/tmp/build/usr/local/kong/lib \
        --with-include-path="/tmp/gmp/" \
        --with-lib-path="/tmp/gmp/.libs/"

    make install -j2 #TODO set this to something sensible

    echo '--- installed nettle ---'
}

main
