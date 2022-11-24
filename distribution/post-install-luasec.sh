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
LUASEC_VERSION="${LUASEC_VERSION:?LUASEC_VERSION is empty/undefined!}"

function main() {
    printf -- '--- SSL_PROVIDER=%q ---\n' \
        "${SSL_PROVIDER:?SSL_PROVIDER is undefined}"

    case $SSL_PROVIDER in
        openssl|boringssl)
            echo "--- installing luasec $LUASEC_VERSION ---"

            /tmp/build/usr/local/bin/luarocks install kong-luasec \
                "$LUASEC_VERSION" \
                CRYPTO_DIR="${CRYPTO_DIR:-/usr/local/kong}" \
                OPENSSL_DIR="${OPENSSL_DIR:-/usr/local/kong}" \
                CFLAGS="-L/tmp/build/usr/local/kong/lib -Wl,-rpath,/usr/local/kong/lib -O2 -std=gnu99 -fPIC" \
            || {
                echo '--- FATAL: failed installing luasec ---'
                exit 1
            }

            echo '--- installed luasec ---'
            ;;

        *)
            printf -- '--- unknown SSL_PROVIDER: %q ---\n' \
                "$SSL_PROVIDER"

            exit 1
            ;;
    esac

}

main
