#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

KONG_DISTRIBUTION_PATH=${KONG_DISTRIBUTION_PATH:-/distribution}

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

function main() {
    for dir in \
        kong-openid-connect \
        lua-resty-openapi3-deserializer \
        kong-gql \
    ; do
        pushd $KONG_DISTRIBUTION_PATH/$dir
            /tmp/build/usr/local/bin/luarocks purge --tree=/tmp/build/usr/local --old-versions || true
            /tmp/build/usr/local/bin/luarocks make *.rockspec \
                CRYPTO_DIR=/usr/local/kong \
                OPENSSL_DIR=/usr/local/kong \
                YAML_LIBDIR=/tmp/build/usr/local/kong/lib \
                YAML_INCDIR=/tmp/yaml
        popd
    done
}

main
