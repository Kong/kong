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

source .requirements

DOWNLOAD_CACHE=${DOWNLOAD_CACHE:-/tmp}

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

function main() {
    echo '--- installing libexpat ---'
    if [ -e /tmp/build/usr/local/kong/lib/libexpat.so ]; then
        echo '--- libexpat already installed ---'
        return
    fi

    if [ ! -d $DOWNLOAD_CACHE/$KONG_DEP_EXPAT_VERSION ]; then
        curl -fsSLo "${DOWNLOAD_CACHE}/expat-${KONG_DEP_EXPAT_VERSION}.tar.gz" \
            "https://github.com/libexpat/libexpat/releases/download/R_${KONG_DEP_EXPAT_VERSION//./_}/expat-${KONG_DEP_EXPAT_VERSION}.tar.gz"

        cd $DOWNLOAD_CACHE
        tar xvf expat-$KONG_DEP_EXPAT_VERSION.tar.gz
        ln -sf $DOWNLOAD_CACHE/expat-$KONG_DEP_EXPAT_VERSION $DOWNLOAD_CACHE/expat
    fi

    cd $DOWNLOAD_CACHE/expat

    ./buildconf.sh

    ./configure \
        --build=$(uname -m)-linux-gnu \
        --enable-static=no \
        --prefix=/tmp/build/usr/local/kong

    make install -j$(nproc)

    echo '--- installed libexpat ---'
}

main
