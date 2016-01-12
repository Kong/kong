#!/bin/bash

set -e

if [ "$TEST_SUITE" == "unit" ]; then
  echo "Exiting, no integration tests"
  exit
fi

mkdir -p $OPENRESTY_DIR

if [ ! "$(ls -A $OPENRESTY_DIR)" ]; then
  # Download OpenSSL
  OPENSSL_BASE=openssl-$OPENSSL_VERSION
  curl http://www.openssl.org/source/$OPENSSL_BASE.tar.gz | tar xz

  # Download OpenResty
  OPENRESTY_BASE=ngx_openresty-$OPENRESTY_VERSION
  curl https://openresty.org/download/$OPENRESTY_BASE.tar.gz | tar xz
  pushd $OPENRESTY_BASE

  # Download and apply nginx patch
  pushd bundle/nginx-*
  wget https://raw.githubusercontent.com/openresty/lua-nginx-module/ssl-cert-by-lua/patches/nginx-ssl-cert.patch --no-check-certificate
  patch -p1 < nginx-ssl-cert.patch
  popd

  # Download `ssl-cert-by-lua` branch
  pushd bundle
  wget https://github.com/openresty/lua-nginx-module/archive/ssl-cert-by-lua.tar.gz -O ssl-cert-by-lua.tar.gz --no-check-certificate
  tar xzf ssl-cert-by-lua.tar.gz
  # Replace `ngx_lua-*` with `ssl-cert-by-lua` branch
  NGX_LUA=`ls | grep ngx_lua-*`
  rm -rf $NGX_LUA
  mv lua-nginx-module-ssl-cert-by-lua $NGX_LUA
  popd

  ./configure \
    --prefix=$OPENRESTY_DIR \
    --with-luajit=$LUAJIT_DIR \
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
