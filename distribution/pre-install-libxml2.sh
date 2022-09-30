#!/usr/bin/env bash

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

    # shellcheck disable=SC2034
    LDFLAGS="-Wl,-rpath,/usr/local/kong/lib"

    ./configure --disable-static \
                --libdir=/tmp/build/usr/local/kong/lib \
                --without-catalog \
                --without-debug \
                --without-html \
                --without-http \
                --without-iconv \
                --without-pattern \
                --without-push \
                --without-python \
                --without-regexps \
                --without-sax1 \
                --without-schemas \
                --without-schematron \
                --without-valid \
                --without-xinclude \
                --without-xpath \
                --without-xptr \
                --without-modules

    make -j2
    make install

    echo '--- installed libxml2 ---'
}

main
