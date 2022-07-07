#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

source .requirements

function main() {
    echo '--- installing gmp ---'
    curl -fsSLo /tmp/gmp-${KONG_GMP_VERSION}.tar.bz2 https://ftp.gnu.org/gnu/gmp/gmp-${KONG_GMP_VERSION}.tar.bz2
    cd /tmp
    tar xjf gmp-${KONG_GMP_VERSION}.tar.bz2
    ln -s /tmp/gmp-${KONG_GMP_VERSION} /tmp/gmp
    cd /tmp/gmp
    echo "'uname -m' = $(uname -m)"
    ./configure \
        --build=$(uname -m)-linux-gnu \
        --enable-static=no \
        --libdir=/tmp/build/usr/local/kong/lib
    make install -j2 #TODO set this to something sensible
    echo '--- installed gmp ---'
}

main
