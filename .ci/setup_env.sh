#!/usr/bin/env bash
set -e

#---------
# Download
#---------
OPENSSL_DOWNLOAD=$DOWNLOAD_CACHE/openssl-$OPENSSL
OPENRESTY_DOWNLOAD=$DOWNLOAD_CACHE/openresty-$OPENRESTY
LUAROCKS_DOWNLOAD=$DOWNLOAD_CACHE/luarocks-$LUAROCKS

mkdir -p $OPENSSL_DOWNLOAD $OPENRESTY_DOWNLOAD $LUAROCKS_DOWNLOAD

if [ ! "$(ls -A $OPENSSL_DOWNLOAD)" ]; then
  pushd $DOWNLOAD_CACHE
    curl -s -S -L http://www.openssl.org/source/openssl-$OPENSSL.tar.gz | tar xz
  popd
fi

if [ ! "$(ls -A $OPENRESTY_DOWNLOAD)" ]; then
  pushd $DOWNLOAD_CACHE
    curl -s -S -L https://openresty.org/download/openresty-$OPENRESTY.tar.gz | tar xz
  popd
fi

if [ ! "$(ls -A $LUAROCKS_DOWNLOAD)" ]; then
  git clone -q https://github.com/keplerproject/luarocks.git $LUAROCKS_DOWNLOAD
fi

#--------
# Install
#--------
OPENSSL_INSTALL=$INSTALL_CACHE/openssl-$OPENSSL
OPENRESTY_INSTALL=$INSTALL_CACHE/openresty-$OPENRESTY
LUAROCKS_INSTALL=$INSTALL_CACHE/luarocks-$LUAROCKS

mkdir -p $OPENSSL_INSTALL $OPENRESTY_INSTALL $LUAROCKS_INSTALL

if [ ! "$(ls -A $OPENSSL_INSTALL)" ]; then
  pushd $OPENSSL_DOWNLOAD
    ./config shared --prefix=$OPENSSL_INSTALL &> build.log || (cat build.log && exit 1)
    make &> build.log || (cat build.log && exit 1)
    make install &> build.log || (cat build.log && exit 1)
  popd
fi

if [ ! "$(ls -A $OPENRESTY_INSTALL)" ]; then
  OPENRESTY_OPTS=(
    "--prefix=$OPENRESTY_INSTALL"
    "--with-openssl=$OPENSSL_DOWNLOAD"
    "--with-ipv6"
    "--with-pcre-jit"
    "--with-http_ssl_module"
    "--with-http_realip_module"
    "--with-http_stub_status_module"
    "--with-http_v2_module"
  )

  pushd $OPENRESTY_DOWNLOAD
    ./configure ${OPENRESTY_OPTS[*]} &> build.log || (cat build.log && exit 1)
    make &> build.log || (cat build.log && exit 1)
    make install &> build.log || (cat build.log && exit 1)
  popd
fi

if [ ! "$(ls -A $LUAROCKS_INSTALL)" ]; then
  pushd $LUAROCKS_DOWNLOAD
    git checkout -q v$LUAROCKS
    ./configure \
      --prefix=$LUAROCKS_INSTALL \
      --lua-suffix=jit \
      --with-lua=$OPENRESTY_INSTALL/luajit \
      --with-lua-include=$OPENRESTY_INSTALL/luajit/include/luajit-2.1 \
      &> build.log || (cat build.log && exit 1)
    make build &> build.log || (cat build.log && exit 1)
    make install &> build.log || (cat build.log && exit 1)
  popd
fi

export OPENSSL_DIR=$OPENSSL_INSTALL # for LuaSec install

export PATH=$PATH:$OPENRESTY_INSTALL/nginx/sbin:$OPENRESTY_INSTALL/bin:$LUAROCKS_INSTALL/bin

eval `luarocks path`

# -------------------------------------
# Install ccm & setup Cassandra cluster
# -------------------------------------
if [[ "$TEST_SUITE" != "unit" ]] && [[ "$TEST_SUITE" != "lint" ]]; then
  pip install --user PyYAML six ccm &> build.log || (cat build.log && exit 1)
  ccm create test -v $CASSANDRA -n 1 -d
  ccm start -v
  ccm status
fi

nginx -V
resty -V
luarocks --version
