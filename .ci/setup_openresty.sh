#!/bin/bash

set -e

if [ "$TEST_SUITE" == "unit" ]; then
  echo "Exiting, no integration tests"
  exit
fi

mkdir -p $OPENRESTY_DIR

if [ ! "$(ls -A $OPENRESTY_DIR)" ]; then
  # Download OpenSSL
  OPENSSL_BASE=openssl-$OPENSSL
  curl http://www.openssl.org/source/$OPENSSL_BASE.tar.gz | tar xz

  # Download OpenResty
  OPENRESTY_BASE=openresty-$OPENRESTY
  curl https://openresty.org/download/$OPENRESTY_BASE.tar.gz | tar xz
  pushd $OPENRESTY_BASE

  ./configure \
    --prefix=$OPENRESTY_DIR \
    --with-luajit=$LUA_DIR \
    --with-openssl=../$OPENSSL_BASE \
    --with-pcre-jit \
    --with-ipv6 \
    --with-http_realip_module \
    --with-http_ssl_module \
    --with-http_stub_status_module

  make
  make install
  popd
fi
