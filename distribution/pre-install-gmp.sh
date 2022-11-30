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
    echo '--- installing gmp ---'
    if [ -e /tmp/build/usr/local/kong/lib/libgmp.so ]; then
        echo '--- gmp already installed ---'
        return
    fi

    if [ ! -d $DOWNLOAD_CACHE/$KONG_GMP_VERSION ]; then
        curl -fsSLo $DOWNLOAD_CACHE/gmp-$KONG_GMP_VERSION.tar.bz2 https://ftp.gnu.org/gnu/gmp/gmp-${KONG_GMP_VERSION}.tar.bz2
        cd $DOWNLOAD_CACHE
        tar xjf gmp-$KONG_GMP_VERSION.tar.bz2
        ln -sf $DOWNLOAD_CACHE/gmp-$KONG_GMP_VERSION $DOWNLOAD_CACHE/gmp
    fi

    cd $DOWNLOAD_CACHE/gmp
    echo "'uname -m' = $(uname -m)"
    ./configure \
        --prefix=$DOWNLOAD_CACHE/gmp \
        --build=$(uname -m)-linux-gnu \
        --enable-static=no \
        --libdir=/tmp/build/usr/local/kong/lib
    make install -j$(nproc)
    echo '--- installed gmp ---'
}

main
