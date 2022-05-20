#!/usr/bin/env bash
# set -e

dep_version() {
    grep $1 .requirements | sed -e 's/.*=//' | tr -d '\n'
}

YQ_VERSION=v4.5.0
OPENRESTY=$(dep_version RESTY_VERSION)
LUAROCKS=$(dep_version RESTY_LUAROCKS_VERSION)
OPENSSL=$(dep_version RESTY_OPENSSL_VERSION)
GO_PLUGINSERVER=$(dep_version KONG_GO_PLUGINSERVER_VERSION)
PCRE=$(dep_version RESTY_PCRE_VERSION)
RESTY_LMDB=$(dep_version RESTY_LMDB_VERSION)
PASSWDQC=$(dep_version KONG_DEP_PASSWDQC_VERSION)
KONG_PGMOON_VERSION=$(dep_version KONG_PGMOON_VERSION)
KONG_DEP_LUA_RESTY_OPENSSL_AUX_MODULE_VERSION=$(dep_version KONG_DEP_LUA_RESTY_OPENSSL_AUX_MODULE_VERSION)

DOWNLOAD_ROOT=${DOWNLOAD_ROOT:=/download-root}
INSTALL_ROOT=${INSTALL_ROOT:=/install-cache}
INSTALL_ROOT_BIN=${INSTALL_ROOT_BIN:=/$INSTALL_ROOT/bin}
mkdir -p "${DOWNLOAD_ROOT}"
mkdir -p "${INSTALL_ROOT}"
mkdir -p "${INSTALL_ROOT_BIN}"

#---------
# Download
#---------

BUILD_TOOLS_DOWNLOAD=$GITHUB_WORKSPACE/kong-build-tools
GO_PLUGINSERVER_DOWNLOAD=$GITHUB_WORKSPACE/go-pluginserver

KONG_NGINX_MODULE_BRANCH=${KONG_NGINX_MODULE_BRANCH:=master}
LUA_RESTY_OPENSSL_AUX_MODULE_DOWNLOAD=${INSTALL_ROOT}/lua-resty-openssl-aux-module
PGMOON_DOWNLOAD=${DOWNLOAD_ROOT}/pgmoon
PONGO_DOWNLOAD=${INSTALL_ROOT}/pongo

wget https://www.openwall.com/passwdqc/passwdqc-${PASSWDQC}.tar.gz \
    -O ${DOWNLOAD_ROOT}/libpasswdqc.tar.gz

wget https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64 \
    -O ${INSTALL_ROOT_BIN}/yq
chmod +x ${INSTALL_ROOT_BIN}/yq

wget https://github.com/tsenart/vegeta/releases/download/v12.8.4/vegeta_12.8.4_linux_amd64.tar.gz \
    -O ${DOWNLOAD_ROOT}/vegeta.tar.gz

git clone -b $KONG_DEP_LUA_RESTY_OPENSSL_AUX_MODULE_VERSION \
    https://github.com/fffonion/lua-resty-openssl-aux-module \
    $LUA_RESTY_OPENSSL_AUX_MODULE_DOWNLOAD

git clone --branch "${KONG_PGMOON_VERSION}" \
    https://github.com/Kong/pgmoon/ \
    ${PGMOON_DOWNLOAD}

git clone https://github.com/Kong/kong-pongo.git \
    ${PONGO_DOWNLOAD}

#--------
# Install
#--------

LIBPASSWDQC_INSTALL=${INSTALL_ROOT}/libpasswdqc
OPENSSL_INSTALL=$INSTALL_ROOT/openssl
OPENRESTY_INSTALL=$INSTALL_ROOT/openresty
LUAROCKS_INSTALL=$INSTALL_ROOT/luarocks

ln -s ${PONGO_DOWNLOAD}/pongo.sh ${INSTALL_ROOT_BIN}/pongo

pushd ${DOWNLOAD_ROOT}
    tar -zxf vegeta.tar.gz
    cp vegeta "${INSTALL_ROOT_BIN}/vegeta"
popd


pushd $DOWNLOAD_ROOT
    mkdir -p libpasswdqc
    tar -zxf "libpasswdqc.tar.gz" -C libpasswdqc --strip-components=1
    pushd libpasswdqc
        make -j $(nproc) \
            BINDIR=$LIBPASSWDQC_INSTALL/bin \
            CONFDIR=$LIBPASSWDQC_INSTALL/etc \
            SHARED_LIBDIR=$LIBPASSWDQC_INSTALL/lib \
            SHARED_LIBDIR_SUN=$LIBPASSWDQC_INSTALL/lib/sun \
            SHARED_LIBDIR_REL=$LIBPASSWDQC_INSTALL/lib \
            DEVEL_LIBDIR=$LIBPASSWDQC_INSTALL/lib \
            SECUREDIR=$LIBPASSWDQC_INSTALL/security \
            SECUREDIR_SUN=$LIBPASSWDQC_INSTALL/security/sun \
            SECUREDIR_DARWIN=$LIBPASSWDQC_INSTALL/security/darwin \
            INCLUDEDIR=$LIBPASSWDQC_INSTALL/include \
            MANDIR=$LIBPASSWDQC_INSTALL/man
        make install \
            -j $(nproc) \
            BINDIR=$LIBPASSWDQC_INSTALL/bin \
            CONFDIR=$LIBPASSWDQC_INSTALL/etc \
            SHARED_LIBDIR=$LIBPASSWDQC_INSTALL/lib \
            SHARED_LIBDIR_SUN=$LIBPASSWDQC_INSTALL/lib/sun \
            SHARED_LIBDIR_REL=$LIBPASSWDQC_INSTALL/lib \
            DEVEL_LIBDIR=$LIBPASSWDQC_INSTALL/lib \
            SECUREDIR=$LIBPASSWDQC_INSTALL/security \
            SECUREDIR_SUN=$LIBPASSWDQC_INSTALL/security/sun \
            SECUREDIR_DARWIN=$LIBPASSWDQC_INSTALL/security/darwin \
            INCLUDEDIR=$LIBPASSWDQC_INSTALL/include \
            MANDIR=$LIBPASSWDQC_INSTALL/man
    popd
popd


export NGX_LUA_LOC="$DOWNLOAD_ROOT/openresty-*/build/ngx_lua-*"


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
    --add-module $LUA_RESTY_OPENSSL_AUX_MODULE_DOWNLOAD \
    --debug

eval $(luarocks path)


pushd $LUA_RESTY_OPENSSL_AUX_MODULE_DOWNLOAD
    make install LUA_LIB_DIR=${OPENRESTY_INSTALL}/lualib
popd


pushd $PGMOON_DOWNLOAD
    luarocks make
popd
rm -rf $PGMOON_DOWNLOAD


nginx -V
resty -V
luarocks --version
openssl version
