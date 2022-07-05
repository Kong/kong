#!/usr/bin/env bash

# Temporary hack to conditionally install luasec until we find a
# better way to support SSL socket in init and init_worker phase in Kong
# BoringSSL won't install luasec; it will also not have SSL socket support
# for now (for example pg_ssl won't work in FIPS build).

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

source .requirements

function main() {
    echo '--- installing luasec ---'

    # TODO: is there a better way to detect what compile flags we are using
    # instead of blindly return true?
    /tmp/build/usr/local/bin/luarocks install luasec || true
    
    echo '--- installed luasec ---'
}

main
