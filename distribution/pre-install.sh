#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

source .requirements

KONG_DISTRIBUTION_PATH=${KONG_DISTRIBUTION_PATH:-/distribution}

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

function main() {
    for script in \
        ./pre-install-gmp.sh \
        ./pre-install-nettle.sh \
        ./pre-install-yaml.sh \
        ./pre-install-libexpat.sh \
        ./pre-install-libxml2.sh \
        ./pre-install-libxslt.sh \
    ; do $KONG_DISTRIBUTION_PATH/$script 2>&1; done
}

main
