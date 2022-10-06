#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

source .requirements

function main() {
    for script in \
        pre-install-gmp.sh \
        pre-install-nettle.sh \
        pre-install-yaml.sh \
        pre-install-libexpat.sh \
    ; do ./$script; done
}

main
