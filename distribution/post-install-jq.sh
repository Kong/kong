#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

source .requirements

function main() {
    echo '--- installing jq ---'
    curl -fsSLo /tmp/jq-${KONG_DEP_LIBJQ_VERSION}.tar.gz https://github.com/stedolan/jq/releases/download/jq-${KONG_DEP_LIBJQ_VERSION}/jq-${KONG_DEP_LIBJQ_VERSION}.tar.gz
    cd /tmp
    tar xzf jq-${KONG_DEP_LIBJQ_VERSION}.tar.gz
    ln -s /tmp/jq-${KONG_DEP_LIBJQ_VERSION} /tmp/jq
    cd /tmp/jq
    ./configure --prefix=/tmp/build/usr/local/kong
    make
    make install
    echo '--- installed jq ---'
}

main
