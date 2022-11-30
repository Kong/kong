#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

source .requirements

KONG_DISTRIBUTION_PATH=${KONG_DISTRIBUTION_PATH:-/distribution}
DOWNLOAD_ROOT=${DOWNLOAD_ROOT:-/work}

if [ -n "${DEBUG:-}" ]; then
    set -x
fi


function main() {
    if [ "${ENABLE_KONG_LICENSING:-}" == "false" ]; then
        echo '--- skipping kong-licensing installation ---'
    else
        echo '--- installing kong-licensing ---'
        pushd $KONG_DISTRIBUTION_PATH/kong-licensing/lib
            CFLAGS="-I$DOWNLOAD_ROOT/openssl/inc" \
            LIBPATH=/tmp/build/usr/local/kong/lib \
            LDFLAGS="-Wl,-rpath,/usr/local/kong/lib -L$DOWNLOAD_ROOT/openssl/inc" \
            make -s \
                -j2 \
                liblicense_utils.so
            cp liblicense_utils.so /tmp/build/usr/local/kong/lib
        popd
        echo '--- installed kong-licensing ---'
    fi
}

main
