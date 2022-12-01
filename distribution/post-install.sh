#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

source .requirements

function main() {
    ROCKS_CONFIG="$(mktemp)"
    echo "
    rocks_trees = {
       { name = [[system]], root = [[/tmp/build/usr/local]] }
    }
    " > $ROCKS_CONFIG

    export LUAROCKS_CONFIG=$ROCKS_CONFIG
    export LUA_PATH="/usr/local/share/lua/5.1/?.lua;/usr/local/openresty/luajit/share/luajit-2.1.0-beta3/?.lua;;"
    export PATH="${PATH}:/usr/local/openresty/luajit/bin:/tmp/build/usr/local/kong/bin"

    # ensure the built jq is accessible for admin/portal install
    export PATH="${PATH}:/tmp/build/usr/local/kong/bin"

    # the order of these scripts unfortunately matters
    for script in \
        post-install-passwdqc.sh \
        post-install-yaml-luarock.sh \
        post-install-openresty-plugins.sh \
        post-install-distributions-constants.sh \
        post-install-apply-patches.sh \
        post-install-openresty-openssl-aux.sh \
        post-install-enterprise-plugins.sh \
        post-install-jq.sh \
        post-install-admin-portal.sh \
        post-install-license-library.sh \
        post-add-copyright-headers.sh \
    ; do ./$script; done

    # see also:
    #   post-bytecompile.sh referenced in kong-build-tools/build-kong.sh
}

main
