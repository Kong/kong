set -e
set -x

#---------
# Download
#---------
OPENSSL_DOWNLOAD=$DOWNLOAD_CACHE/openssl-$OPENSSL
OPENRESTY_DOWNLOAD=$DOWNLOAD_CACHE/openresty-$OPENRESTY
LUAROCKS_DOWNLOAD=$DOWNLOAD_CACHE/luarocks-$LUAROCKS
SERF_DOWNLOAD=$DOWNLOAD_CACHE/serf-$SERF

mkdir -p $OPENSSL_DOWNLOAD $OPENRESTY_DOWNLOAD $LUAROCKS_DOWNLOAD $SERF_DOWNLOAD

if [ ! "$(ls -A $OPENSSL_DOWNLOAD)" ]; then
  pushd $DOWNLOAD_CACHE
    curl -L http://www.openssl.org/source/openssl-$OPENSSL.tar.gz | tar xz
  popd
fi

if [ ! "$(ls -A $OPENRESTY_DOWNLOAD)" ]; then
  pushd $DOWNLOAD_CACHE
    curl -L https://openresty.org/download/openresty-$OPENRESTY.tar.gz | tar xz
  popd
fi

if [ ! "$(ls -A $LUAROCKS_DOWNLOAD)" ]; then
  git clone https://github.com/keplerproject/luarocks.git $LUAROCKS_DOWNLOAD
fi

if [ ! "$(ls -A $SERF_DOWNLOAD)" ]; then
  pushd $SERF_DOWNLOAD
    wget https://releases.hashicorp.com/serf/${SERF}/serf_${SERF}_linux_amd64.zip
    unzip serf_${SERF}_linux_amd64.zip
  popd
fi

#--------
# Install
#--------
OPENSSL_INSTALL=$INSTALL_CACHE/openssl-$OPENSSL
OPENRESTY_INSTALL=$INSTALL_CACHE/openresty-$OPENRESTY
LUAROCKS_INSTALL=$INSTALL_CACHE/luarocks-$LUAROCKS
SERF_INSTALL=$INSTALL_CACHE/serf-$SERF

mkdir -p $OPENSSL_INSTALL $OPENRESTY_INSTALL $LUAROCKS_INSTALL $SERF_INSTALL

if [ ! "$(ls -A $OPENSSL_INSTALL)" ]; then
  pushd $OPENSSL_DOWNLOAD
    ./config shared --prefix=$OPENSSL_INSTALL
    make
    make install
  popd
fi

if [ ! "$(ls -A $OPENRESTY_INSTALL)" ]; then
  pushd $OPENRESTY_DOWNLOAD
    ./configure \
      --prefix=$OPENRESTY_INSTALL \
      --with-openssl=$OPENSSL_DOWNLOAD \
      --with-ipv6 \
      --with-pcre-jit \
      --with-http_ssl_module \
      --with-http_realip_module \
      --with-http_stub_status_module
    make
    make install
  popd
fi

if [ ! "$(ls -A $LUAROCKS_INSTALL)" ]; then
  pushd $LUAROCKS_DOWNLOAD
    git checkout v$LUAROCKS
    ./configure \
      --prefix=$LUAROCKS_INSTALL \
      --lua-suffix=jit \
      --with-lua=$OPENRESTY_INSTALL/luajit \
      --with-lua-include=$OPENRESTY_INSTALL/luajit/include/luajit-2.1
    make build
    make install
  popd
fi

if [ ! "$(ls -A $SERF_INSTALL)" ]; then
  ln -s $SERF_DOWNLOAD/serf $SERF_INSTALL/serf
fi

export OPENSSL_DIR=$OPENSSL_INSTALL # for LuaSec install
export SERF_PATH=$SERF_INSTALL/serf # for our test instance (not in default bin/sh $PATH)

export PATH=$PATH:$OPENRESTY_INSTALL/nginx/sbin:$OPENRESTY_INSTALL/bin:$LUAROCKS_INSTALL/bin:$SERF_INSTALL

eval `luarocks path`

# -------------------------------------
# Install ccm & setup Cassandra cluster
# -------------------------------------
if [[ "$TEST_SUITE" != "unit" ]] && [[ "$TEST_SUITE" != "lint" ]]; then
  pip install --user PyYAML six
  git clone https://github.com/pcmanus/ccm.git
  pushd ccm
    ./setup.py install --user
  popd
  ccm create test -v binary:$CASSANDRA -n 1 -d
  ccm start -v
  ccm status
fi

nginx -V
resty -V
luarocks --version
serf version
