#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

source .requirements

function main() {
    echo '--- installing lua-yaml (lyaml) ---'
    cp -R /tmp/build/* /

    /usr/local/bin/luarocks install lyaml ${LYAML_VERSION} \
        YAML_LIBDIR=/tmp/build/usr/local/kong/lib \
        YAML_INCDIR=/tmp/yaml CFLAGS="-L/tmp/build/usr/local/kong/lib -Wl,-rpath,/usr/local/kong/lib -O2 -fPIC"
    echo '--- installed lua-yaml (lyaml) ---'
}

main
