#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

source .requirements

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

function main() {
    echo '--- installing lua-yaml (lyaml) ---'

    # Compatable with Kong Build Tools
    if [ -z "${BAZEL_BUILD:-}" ]; then
        cp -R /tmp/build/* / || true
    fi

    /tmp/build/usr/local/bin/luarocks purge --tree=/tmp/build/usr/local --old-versions || true
    /tmp/build/usr/local/bin/luarocks install lyaml ${LYAML_VERSION} \
        YAML_LIBDIR=/tmp/build/usr/local/kong/lib \
        YAML_INCDIR=/tmp/yaml CFLAGS="-L/tmp/build/usr/local/kong/lib -Wl,-rpath,/usr/local/kong/lib -O2 -fPIC"
    echo '--- installed lua-yaml (lyaml) ---'
}

main
