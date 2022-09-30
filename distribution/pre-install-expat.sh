#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

source .requirements

function main() {
    echo '--- installing expat ---'

    cd /tmp
    curl -fsSLO https://github.com/libexpat/libexpat/releases/download/R_$(echo $KONG_DEP_EXPAT_VERSION | tr . _)/expat-${KONG_DEP_EXPAT_VERSION}.tar.gz
    tar xzf expat-${KONG_DEP_EXPAT_VERSION}.tar.gz
    cd expat-${KONG_DEP_EXPAT_VERSION}

    # shellcheck disable=SC2034
    LDFLAGS="-Wl,-rpath,/usr/local/kong/lib"

    ./configure --disable-static \
        --libdir=/tmp/build/usr/local/kong/lib

    make
    make install

    echo '--- installed expat ---'
}

main
