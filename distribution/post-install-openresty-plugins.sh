#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

function main() {
    for dir in \
        kong-openid-connect \
        openapi2kong \
        lua-resty-openapi3-deserializer \
        kong-gql \
    ; do
        pushd $dir
            /usr/local/bin/luarocks make *.rockspec \
                CRYPTO_DIR=/usr/local/kong \
                OPENSSL_DIR=/usr/local/kong \
                YAML_LIBDIR=/tmp/build/usr/local/kong/lib \
                YAML_INCDIR=/tmp/yaml
        popd
    done
}

main
