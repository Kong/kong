#!/usr/bin/env bash

#####
#
# add the libxslt library
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
    echo '--- installing libxslt ---'
    if [ -e /tmp/build/usr/local/kong/lib/libxslt.so ]; then
        echo '--- libxslt already installed ---'
        return
    fi

    if [ ! -d $DOWNLOAD_CACHE/$KONG_DEP_LIBXSLT_VERSION ]; then
        cd $DOWNLOAD_CACHE
        curl -fsSLO https://download.gnome.org/sources/libxslt/$(echo ${KONG_DEP_LIBXSLT_VERSION} | sed -e 's/\.[0-9]*$//')/libxslt-${KONG_DEP_LIBXSLT_VERSION}.tar.xz
        tar xJf libxslt-${KONG_DEP_LIBXSLT_VERSION}.tar.xz
        ln -sf $DOWNLOAD_CACHE/libxslt-$KONG_DEP_LIBXSLT_VERSION $DOWNLOAD_CACHE/libxslt
    fi

    cd $DOWNLOAD_CACHE/libxslt

    PREFIX=/tmp/build/usr/local/kong

    PATH=$PREFIX/bin:$PATH ./configure \
        --build=$(uname -m)-linux-gnu \
        --enable-static=no \
        --prefix=$PREFIX \
	    --without-python

    make install -j$(nproc)

    echo '--- installed libxslt ---'
}

main
