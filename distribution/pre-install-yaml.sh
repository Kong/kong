#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

source .requirements

DOWNLOAD_CACHE=${DOWNLOAD_CACHE:-/tmp}

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

function main() {
    echo '--- installing libyaml ---'
    if [ -e /tmp/build/usr/local/kong/lib/libyaml.so ]; then
        echo '--- libyaml already installed ---'
        return
    fi

    if [ ! -d $DOWNLOAD_CACHE/$KONG_DEP_LIBYAML_VERSION ]; then
        curl -fsSLo $DOWNLOAD_CACHE/yaml-${KONG_DEP_LIBYAML_VERSION}.tar.gz https://pyyaml.org/download/libyaml/yaml-${KONG_DEP_LIBYAML_VERSION}.tar.gz
        cd $DOWNLOAD_CACHE
        tar xzf yaml-${KONG_DEP_LIBYAML_VERSION}.tar.gz
        ln -sf $DOWNLOAD_CACHE/yaml-${KONG_DEP_LIBYAML_VERSION} $DOWNLOAD_CACHE/yaml
    fi

    cd $DOWNLOAD_CACHE/yaml
    ./configure \
        --libdir=/tmp/build/usr/local/kong/lib \
        --includedir=$DOWNLOAD_CACHE/yaml

    make install -j$(nproc)
    echo '--- installed pyyaml ---'
}

main
