#!/bin/bash

source ./versions.sh

OPENRESTY_BASE=ngx_openresty-$OPENRESTY_VERSION

sudo apt-get update && sudo apt-get install libreadline-dev libncurses5-dev libpcre3-dev libssl-dev perl make

curl http://openresty.org/download/$OPENRESTY_BASE.tar.gz | tar xz
cd $OPENRESTY_BASE
./configure --with-pcre-jit --with-ipv6 --with-http_realip_module --with-http_ssl_module --with-http_stub_status_module
make && sudo make install
cd $TRAVIS_BUILD_DIR
rm -rf $OPENRESTY_BASE
