#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

source .requirements

DOWNLOAD_CACHE=${DOWNLOAD_CACHE:-/tmp}

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

function main() {
    echo '--- installing nettle ---'
    if [ -e /tmp/build/usr/local/kong/lib/libnettle.so ]; then
        echo '--- nettle already installed ---'
        return
    fi

    if [ ! -d $DOWNLOAD_CACHE/$KONG_DEP_NETTLE_VERSION ]; then
        curl -fsSLo $DOWNLOAD_CACHE/nettle-${KONG_DEP_NETTLE_VERSION}.tar.gz https://ftp.gnu.org/gnu/nettle/nettle-${KONG_DEP_NETTLE_VERSION}.tar.gz
        cd $DOWNLOAD_CACHE
        tar xzf nettle-${KONG_DEP_NETTLE_VERSION}.tar.gz
        ln -sf $DOWNLOAD_CACHE/nettle-${KONG_DEP_NETTLE_VERSION} $DOWNLOAD_CACHE/nettle
    fi

    cd $DOWNLOAD_CACHE/nettle

    # shellcheck disable=SC2034
    LDFLAGS="-Wl,-rpath,/usr/local/kong/lib"

    ./configure --disable-static \
        --prefix=$DOWNLOAD_CACHE/nettle \
        --libdir=/tmp/build/usr/local/kong/lib \
        --with-include-path="${DOWNLOAD_CACHE}/gmp/" \
        --with-lib-path="${DOWNLOAD_CACHE}/gmp/.libs/"

    make install -j$(nproc)

    echo '--- installed nettle ---'
}

main
