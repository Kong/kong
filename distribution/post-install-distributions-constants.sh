#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

KONG_DISTRIBUTION_PATH=${KONG_DISTRIBUTION_PATH:-/distribution}
KONG_SOURCE_PATH=${KONG_SOURCE_PATH:-/kong}

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

function main() {
    cp $KONG_DISTRIBUTION_PATH/distributions_constants.lua $KONG_SOURCE_PATH/kong/enterprise_edition/distributions_constants.lua
}

main
