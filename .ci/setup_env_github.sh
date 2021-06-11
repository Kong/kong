#!/usr/bin/env bash
# set -e

dep_version() {
    grep $1 .requirements | sed -e 's/.*=//' | tr -d '\n'
}

OPENRESTY=$(dep_version RESTY_VERSION)
LUAROCKS=$(dep_version RESTY_LUAROCKS_VERSION)
OPENSSL=$(dep_version RESTY_OPENSSL_VERSION)
GO_PLUGINSERVER=$(dep_version KONG_GO_PLUGINSERVER_VERSION)
PCRE=$(dep_version RESTY_PCRE_VERSION)


#---------
# Download
#---------

DOWNLOAD_ROOT=${DOWNLOAD_ROOT:=/download-root}
BUILD_TOOLS_DOWNLOAD=$GITHUB_WORKSPACE/kong-build-tools
GO_PLUGINSERVER_DOWNLOAD=$GITHUB_WORKSPACE/go-pluginserver

KONG_NGINX_MODULE_BRANCH=${KONG_NGINX_MODULE_BRANCH:=master}

#--------
# Install
#--------
INSTALL_ROOT=${INSTALL_ROOT:=/install-cache}

pushd $GO_PLUGINSERVER_DOWNLOAD
  go get ./...
  make

  mkdir -p $INSTALL_ROOT/go-pluginserver
  cp go-pluginserver $INSTALL_ROOT/go-pluginserver/
popd

kong-ngx-build \
    --work $DOWNLOAD_ROOT \
    --prefix $INSTALL_ROOT \
    --openresty $OPENRESTY \
    --kong-nginx-module $KONG_NGINX_MODULE_BRANCH \
    --luarocks $LUAROCKS \
    --openssl $OPENSSL \
    --pcre $PCRE \
    --debug

OPENSSL_INSTALL=$INSTALL_ROOT/openssl
OPENRESTY_INSTALL=$INSTALL_ROOT/openresty
LUAROCKS_INSTALL=$INSTALL_ROOT/luarocks

eval `luarocks path`

nginx -V
resty -V
luarocks --version
openssl version
