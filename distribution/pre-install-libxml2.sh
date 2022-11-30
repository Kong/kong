#!/usr/bin/env bash

#####
#
# add the libxml2 library
#
# this library is required for the SAML plugin
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
    echo '--- installing libxml2 ---'
    if [ -e /tmp/build/usr/local/kong/lib/libxml2.so ]; then
        echo '--- libxml2 already installed ---'
        return
    fi

    if [ ! -d $DOWNLOAD_CACHE/$KONG_DEP_LIBXML2_VERSION ]; then
        cd $DOWNLOAD_CACHE
        curl -fsSLO https://download.gnome.org/sources/libxml2/$(echo ${KONG_DEP_LIBXML2_VERSION} | sed -e 's/\.[0-9]*$//')/libxml2-${KONG_DEP_LIBXML2_VERSION}.tar.xz
        tar xJf libxml2-$KONG_DEP_LIBXML2_VERSION.tar.xz
        ln -sf $DOWNLOAD_CACHE/libxml2-$KONG_DEP_LIBXML2_VERSION $DOWNLOAD_CACHE/libxml2
    fi

    cd $DOWNLOAD_CACHE/libxml2

    ./configure \
        --build=$(uname -m)-linux-gnu \
        --enable-static=no \
        --prefix=/tmp/build/usr/local/kong \
        --without-http \
        --without-iconv \
        --without-python

    make install -j$(nproc)

    echo '--- installed libxml2 ---'
}

main
