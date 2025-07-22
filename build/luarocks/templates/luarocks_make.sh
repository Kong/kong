#!/bin/bash -e

# template variables starts
luarocks_exec="{{@@luarocks//:luarocks_exec}}"
# template variables ends

if [[ "$OSTYPE" == "darwin"* ]]; then
    export DEVELOPER_DIR=$(xcode-select -p)
    export SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
fi
mkdir -p $(dirname $@)
# lyaml needs this and doesn't honor --no-doc
# the alternate will populate a non-existent HOME
# env var just to let ldoc happy
# alias LDOC command to true(1) command
export LDOC=true

if [ -f kong-latest.rockspec ]; then
    version=$(grep -E '^\s*(major|minor|patch)\s*=' kong/meta.lua \
        | sed -E 's/[^0-9]*([0-9]+).*/\1/' \
        | paste -sd. -)

    tmpfile=$(mktemp kong-rockspec.XXXX)
    sed "s/^version *= *\".*\"/version = \"$version-0\"/" kong-latest.rockspec > "$tmpfile"
    mv "$tmpfile" kong-latest.rockspec

    mv kong-latest.rockspec kong-$version-0.rockspec
fi

$luarocks_exec make --no-doc >$@.tmp 2>&1

# only generate the output when the command succeeds
mv $@.tmp $@
