#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

function main() {
    pushd /distribution/lua-resty-openssl-aux-module
        make install LUA_LIB_DIR=/tmp/build/usr/local/openresty/lualib
    popd
}

main
