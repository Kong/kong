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

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

source .requirements

function main() {
    echo '--- installing libxml2 ---'

    cd /tmp
    curl -fsSLO https://download.gnome.org/sources/libxml2/$(echo ${KONG_DEP_LIBXML2_VERSION} | sed -e 's/\.[0-9]*$//')/libxml2-${KONG_DEP_LIBXML2_VERSION}.tar.xz
    tar xJf libxml2-${KONG_DEP_LIBXML2_VERSION}.tar.xz
    cd libxml2-${KONG_DEP_LIBXML2_VERSION}

    ./configure \
        --build=$(uname -m)-linux-gnu \
        --enable-static=no \
        --prefix=/tmp/build/usr/local/kong \
        --without-catalog \
        --without-debug \
        --without-html \
        --without-http \
        --without-iconv \
        --without-python \
        --without-sax1 \
        --without-schemas \
        --without-schematron \
        --without-valid \
        --without-xinclude \
        --without-xptr \
        --without-modules


    make install -j $(( $(nproc) / 2 ))

    echo '--- installed libxml2 ---'
}

main
