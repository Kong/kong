#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

function main() {
    cp distributions_constants.lua /kong/kong/enterprise_edition/distributions_constants.lua
}

main
