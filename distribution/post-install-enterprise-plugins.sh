#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

function main() {
    echo '--- installing kong-enterprise plugins ---'
    pushd /kong
        make install-plugins-ee #move the script to here someday
    popd
    cp -R /usr/local/lib /tmp/build/usr/local/
    cp -R /usr/local/share/lua /tmp/build/usr/local/share/
    luarocks purge --tree=/tmp/build/usr/local --old-versions
    echo '--- installed kong-enterprise plugins ---'
}
main
