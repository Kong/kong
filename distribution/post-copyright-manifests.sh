#!/usr/bin/env bash

#####
#
# collect copyright manifests
#
# this script's filename must match its invocation in kong-build-tools/build-kong.sh
#
# see also: the copyright-generator repo
#
#####

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-1}" ]; then
    set -x
fi

function main() {
    echo '--- collecting copyright manifests ---'

    local _luarocks _jq

    # the jq installed earlier should suffice
    function _jq() {
        /tmp/build/usr/local/kong/bin/jq "$@"
    }

    # modify the luarocks wrapper script to point to an executable luajit
    _luarocks="$(mktemp /tmp/luarocks.XXXXXXXXX)"
    cp -vf "/tmp/build/usr/local/bin/luarocks" "$_luarocks"

    luajit_path='/usr/local/openresty/luajit/bin/luajit'

    sed -i "s_${luajit_path}_/tmp/build/${luajit_path}_" "$_luarocks"
    chmod a+x "$_luarocks"


    echo "creating manifest of $(
            "$_luarocks" list --porcelain | wc -l
        ) luarocks"

    # turn off command echo since there are loooooooooots of loops
    set +x || true

    # shellcheck disable=SC2016
    "$_luarocks" list --porcelain \
        | while read -r _name _version _unused; do

            # iterate through luarocks outputting a json object per package
            _jq -nM \
                --arg name "$_name" \
                --arg version "$_version" \
                --arg license "$(
                    "$_luarocks" show --rock-license "$_name"
                )" \
                --arg homepage "$(
                    "$_luarocks" show --home "$_name"
                )" \
                '{
                    "name": $name,
                    "version": $version,
                    "license": $license,
                    "homepage": $homepage
                }'

            >&2 echo "adding to manifest ${_name} @ ${_version}"

            unset _name _version

        # finally output a large json object containing the per-package info
        # and write it to a path that gets packages
        done \
            | _jq -s \
                '{
                    "schema_version": "1",
                    "product": {
                        "name": "Kong Gateway",
                        "luarocks": .
                    }
                }' \
                    > '/tmp/build/usr/local/kong/manifest.json'

    # just to  validate the resulting file is writeable/valid/etc.
    _jq '.' '/tmp/build/usr/local/kong/manifest.json'

    # re-enable command echo is DEBUG set
    if [ -n "${DEBUG:-}" ]; then
        set -x
    fi

    echo '--- collected copyright manifests ---'
}

main
