#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

source .requirements

function main() {
    echo '--- installing pyyaml ---'
    curl -fsSLo /tmp/yaml-${KONG_DEP_LIBYAML_VERSION}.tar.gz https://pyyaml.org/download/libyaml/yaml-${KONG_DEP_LIBYAML_VERSION}.tar.gz
    cd /tmp
    tar xzf yaml-${KONG_DEP_LIBYAML_VERSION}.tar.gz
    ln -s /tmp/yaml-${KONG_DEP_LIBYAML_VERSION} /tmp/yaml
    cd /tmp/yaml
    ./configure \
        --libdir=/tmp/build/usr/local/kong/lib \
        --includedir=/tmp/yaml
    
    make install -j2
    echo '--- installed pyyaml ---'
}

main
