#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

source .requirements

function main() {
    ./pre-install-gmp.sh
    ./pre-install-nettle.sh
    ./pre-install-yaml.sh
    ./pre-install-libexpat.sh
    ./pre-install-libxml2.sh
}

main
