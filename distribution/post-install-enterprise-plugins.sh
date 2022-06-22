#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

function main() {
    pushd /kong
        make install-plugins-ee #move the script to here someday
    popd
    cp -R /usr/local/lib /tmp/build/usr/local/
    luarocks purge --tree=/tmp/build/usr/local --old-versions
}
main
