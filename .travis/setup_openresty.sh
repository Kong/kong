#!/bin/bash

OPENRESTY_BASE=ngx_openresty-$OPENRESTY

sudo apt-get update && sudo apt-get install libreadline-dev libncurses5-dev libpcre3-dev libssl-dev perl make

curl http://openresty.org/download/$OPENRESTY_BASE.tar.gz | tar xz
cd $OPENRESTY_BASE
./configure
make && sudo make install
cd $TRAVIS_BUILD_DIR
rm -rf $OPENRESTY_BASE
