#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

function main() {
    echo '--- installing kong-licensing ---'
    pushd /distribution/kong-licensing/lib
        CFLAGS="-I/work/openssl/inc" \
        LIBPATH=/tmp/build/usr/local/kong/lib \
        LDFLAGS="-Wl,-rpath,/usr/local/kong/lib -L/work/openssl/inc" \
        make -s \
            -j2 \
            liblicense_utils.so
        cp liblicense_utils.so /tmp/build/usr/local/kong/lib
    popd
    echo '--- installed kong-licensing ---'
}

main
