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

$luarocks_exec make --no-doc 2>&1 >$@.tmp

# only generate the output when the command succeeds
mv $@.tmp $@