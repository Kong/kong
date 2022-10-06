#!/usr/bin/env bash

#####
#
# add the expat XML processing library
#
# this library is required for the xml-threat plugin
# see also:
#   - https://github.com/libexpat/libexpat#building-from-a-git-clone
#   - https://github.com/Kong/kong-ee/pull/3145#issuecomment-1257742584
#
# TODO: have the xml-threat plugin provide/compile it's own expat
#
#####

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

source .requirements

function main() {
    echo '--- installing libexpat ---'

    curl -fsSLo "/tmp/expat-${KONG_DEP_EXPAT_VERSION}.tar.gz" \
        "https://github.com/libexpat/libexpat/archive/refs/tags/R_${KONG_DEP_EXPAT_VERSION//./_}.tar.gz"

    cd /tmp
    tar xvf expat-${KONG_DEP_EXPAT_VERSION}.tar.gz
    cd ./libexpat-*/expat

    ./buildconf.sh

    ./configure \
        --build=$(uname -m)-linux-gnu \
        --enable-static=no \
        --libdir=/tmp/build/usr/local/kong/lib

    make install -j $(( $(nproc) / 2 ))

    echo '--- installed libexpat ---'
}

main
