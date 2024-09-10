#!/bin/bash -e

# template variables starts
luarocks_exec="{{@@luarocks//:luarocks_exec}}"
jq="{{@@jq//:libjq}}"
source_dir="{{source_dir}}"
# template variables ends

_jq=$jq/bin/jq

"$luarocks_exec" list --porcelain | grep 'installed' \
    | while read -r _name _version _unused; do

    # iterate through luarocks outputting a json object per package
    "$_jq" -nM \
        --arg name "$_name" \
        --arg version "$_version" \
        --arg license "$(
            "$luarocks_exec" show --rock-license "$_name"
        )" \
        --arg homepage "$(
            "$luarocks_exec" show --home "$_name"
        )" \
        '{
            "name": $name,
            "version": $version,
            "license": $license,
            "homepage": $homepage
        }'

    >&2

    unset _name _version

    # finally output a large json object containing the per-package info
    # and write it to a path that gets packages
    done \
        | "$_jq" -s \
            '{
                "schema_version": "1",
                "product": {
                    "name": "Kong Gateway",
                    "luarocks": .
                }
            }' \
                > $@

# just to  validate the resulting file is writeable/valid/etc.
"$_jq" '.' "$@" >/dev/null