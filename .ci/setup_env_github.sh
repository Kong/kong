#!/usr/bin/env bash
# set -e

dep_version() {
    grep $1 .requirements | sed -e 's/.*=//' | tr -d '\n'
}

OPENRESTY=$(dep_version RESTY_VERSION)
LUAROCKS=$(dep_version RESTY_LUAROCKS_VERSION)
OPENSSL=$(dep_version RESTY_OPENSSL_VERSION)
PCRE=$(dep_version RESTY_PCRE_VERSION)
RESTY_LMDB=$(dep_version RESTY_LMDB_VERSION)
RESTY_EVENTS=$(dep_version RESTY_EVENTS_VERSION)
RESTY_WEBSOCKET=$(dep_version RESTY_WEBSOCKET_VERSION)
ATC_ROUTER_VERSION=$(dep_version ATC_ROUTER_VERSION)
KONG_NGINX_MODULE_BRANCH=$(dep_version KONG_NGINX_MODULE_BRANCH)


#---------
# Download
#---------

DOWNLOAD_ROOT=${DOWNLOAD_ROOT:=/download-root}
BUILD_TOOLS_DOWNLOAD=$GITHUB_WORKSPACE/kong-build-tools

#--------
# Install
#--------
INSTALL_ROOT=${INSTALL_ROOT:=/install-cache}

kong-ngx-build \
    --work $DOWNLOAD_ROOT \
    --prefix $INSTALL_ROOT \
    --openresty $OPENRESTY \
    --kong-nginx-module $KONG_NGINX_MODULE_BRANCH \
    --luarocks $LUAROCKS \
    --openssl $OPENSSL \
    --resty-lmdb $RESTY_LMDB \
    --resty-events $RESTY_EVENTS \
    --resty-websocket $RESTY_WEBSOCKET \
    --pcre $PCRE \
    --atc-router $ATC_ROUTER_VERSION \
    --debug

OPENSSL_INSTALL=$INSTALL_ROOT/openssl
OPENRESTY_INSTALL=$INSTALL_ROOT/openresty
LUAROCKS_INSTALL=$INSTALL_ROOT/luarocks

eval `luarocks path`

nginx -V
resty -V
luarocks --version
openssl version
