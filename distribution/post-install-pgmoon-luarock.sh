#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

source .requirements

function main() {
    echo '--- installing pgmoon (from Kong fork) ---'

    # remove pgmoon if installed (unlikely)
    /tmp/build/usr/local/bin/luarocks remove pgmoon --force || true

    # use our own fork of pgmoon
    git clone https://github.com/Kong/pgmoon /tmp/pgmoon

    cd /tmp/pgmoon

    git reset --hard "${KONG_DEP_PGMOON_VERSION:-2.2.2}"

    CFLAGS="-L/tmp/build/usr/local/kong/lib -Wl,-rpath,/usr/local/kong/lib -O2 -fPIC" \
        /tmp/build/usr/local/bin/luarocks make --force

    rm -rf /tmp/pgmoon

    echo '--- installed pgmoon (from Kong fork) ---'
}

main
