#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

function main() {
    if [ -z "${ENABLE_ANONYMOUS_REPORTS:-}" ]; then
        echo "\$ENABLE_ANONYMOUS_REPORTS not set, skipping kong.conf patch"
    else
        echo "\$ENABLE_ANONYMOUS_REPORTS set, patching kong.conf"

        pushd /kong
            shopt -s nullglob
            patch -p1 < /distribution/patches/anon_default_off.patch || exit 1
            shopt -u nullglob
        popd
    fi

    if [ -z "${ENABLE_GDIT_PATCH:-}" ]; then
        echo "\$ENABLE_GDIT_PATCH not set, skipping LICENSE patch"
    else
        echo "\$ENABLE_GDIT_PATCH set, patching LICENSE"

        pushd /kong
            shopt -s nullglob
            patch -p1 < /distribution/patches/GDIT.patch || exit 1
            shopt -u nullglob
        popd
    fi
}

main
