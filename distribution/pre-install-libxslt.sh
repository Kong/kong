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

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

source .requirements

function main() {
    echo '--- installing libxslt ---'

    cd /tmp
    curl -fsSLO https://download.gnome.org/sources/libxslt/$(echo ${KONG_DEP_LIBXSLT_VERSION} | sed -e 's/\.[0-9]*$//')/libxslt-${KONG_DEP_LIBXSLT_VERSION}.tar.xz
    tar xJf libxslt-${KONG_DEP_LIBXSLT_VERSION}.tar.xz
    cd libxslt-${KONG_DEP_LIBXSLT_VERSION}

    ./configure \
        --build=$(uname -m)-linux-gnu \
        --enable-static=no \
        --prefix=/tmp/build/usr/local/kong \
	--without-python

    make install -j $(( $(nproc) / 2 ))

    echo '--- installed libxslt ---'
}

main
