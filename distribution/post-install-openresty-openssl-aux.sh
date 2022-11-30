#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

KONG_DISTRIBUTION_PATH=${KONG_DISTRIBUTION_PATH:-/distribution}

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

function main() {
    pushd $KONG_DISTRIBUTION_PATH/lua-resty-openssl-aux-module
        make install LUA_LIB_DIR=/tmp/build/usr/local/openresty/lualib
    popd
}

main
