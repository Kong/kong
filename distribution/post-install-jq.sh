#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

source .requirements

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

function main() {
    echo '--- installing jq ---'
    if [ -e /tmp/build/usr/local/kong/bin/jq ]; then
        echo '--- jq already installed ---'
        return
    fi

    curl -fsSLo /tmp/jq-${KONG_DEP_LIBJQ_VERSION}.tar.gz https://github.com/stedolan/jq/releases/download/jq-${KONG_DEP_LIBJQ_VERSION}/jq-${KONG_DEP_LIBJQ_VERSION}.tar.gz
    cd /tmp
    tar xzf jq-${KONG_DEP_LIBJQ_VERSION}.tar.gz
    ln -sf /tmp/jq-${KONG_DEP_LIBJQ_VERSION} /tmp/jq
    cd /tmp/jq
    ./configure --prefix=/tmp/build/usr/local/kong
    make
    make install
    echo '--- installed jq ---'
}

main
