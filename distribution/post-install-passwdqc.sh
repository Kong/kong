#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

source .requirements

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

function main() {
    echo '--- installing passwdqc ---'
    if [ -e /tmp/build/usr/local/kong/lib/libpasswdqc.so ]; then
        echo '--- passwdqc already installed ---'
        return
    fi

    curl -fsSLo /tmp/passwdqc-${KONG_DEP_PASSWDQC_VERSION}.tar.gz https://www.openwall.com/passwdqc/passwdqc-${KONG_DEP_PASSWDQC_VERSION}.tar.gz
    cd /tmp
    tar xzf passwdqc-${KONG_DEP_PASSWDQC_VERSION}.tar.gz
    ln -sf /tmp/passwdqc-${KONG_DEP_PASSWDQC_VERSION} /tmp/passwdqc
    cd /tmp/passwdqc
    make libpasswdqc.so -j2 #TODO set this to something sensible
    make \
        DESTDIR=/tmp/build/ \
        SHARED_LIBDIR=/usr/local/kong/lib \
        SHARED_LIBDIR_REL='.' \
        DEVEL_LIBDIR=/usr/local/kong/lib \
        INCLUDEDIR=/usr/local/kong/include/passwdqc \
        CONFDIR=/usr/local/etc/passwdqc \
        MANDIR=/usr/local/share/man \
        install_lib
    echo '--- installed passwdqc ---'
}

main
