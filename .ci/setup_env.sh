set -e

export OPENRESTY_INSTALL=$CACHE_DIR/openresty
export LUAROCKS_INSTALL=$CACHE_DIR/luarocks
export SERF_INSTALL=$CACHE_DIR/serf

mkdir -p $CACHE_DIR

if [ ! "$(ls -A $CACHE_DIR)" ]; then
  # Not in cache

  # ---------------
  # Install OpenSSL
  # ---------------
  OPENSSL_BASE=openssl-$OPENSSL
  curl -L http://www.openssl.org/source/$OPENSSL_BASE.tar.gz | tar xz

  # -----------------
  # Install OpenResty
  # -----------------
  OPENRESTY_BASE=openresty-$OPENRESTY
  mkdir -p $OPENRESTY_INSTALL
  curl -L https://openresty.org/download/$OPENRESTY_BASE.tar.gz | tar xz

  pushd $OPENRESTY_BASE
    ./configure \
      --prefix=$OPENRESTY_INSTALL \
      --with-openssl=../$OPENSSL_BASE \
      --with-ipv6 \
      --with-pcre-jit \
      --with-http_ssl_module \
      --with-http_realip_module \
      --with-http_stub_status_module \
      --without-lua_resty_websocket \
      --without-lua_resty_upload \
      --without-lua_resty_mysql \
      --without-lua_resty_redis \
      --without-http_redis_module \
      --without-http_redis2_module \
      --without-lua_redis_parser
    make
    make install
  popd

  rm -rf $OPENRESTY_BASE

  # ----------------
  # Install Luarocks
  # ----------------
  LUAROCKS_BASE=luarocks-$LUAROCKS
  mkdir -p $LUAROCKS_INSTALL
  git clone https://github.com/keplerproject/luarocks.git $LUAROCKS_BASE

  pushd $LUAROCKS_BASE
    git checkout v$LUAROCKS
    ./configure \
      --prefix=$LUAROCKS_INSTALL \
      --lua-suffix=jit \
      --with-lua=$OPENRESTY_INSTALL/luajit \
      --with-lua-include=$OPENRESTY_INSTALL/luajit/include/luajit-2.1
    make build
    make install
  popd

  rm -rf $LUAROCKS_BASE

  # ------------
  # Install Serf
  # ------------
  mkdir -p $SERF_INSTALL
  pushd $SERF_INSTALL
    wget https://releases.hashicorp.com/serf/${SERF}/serf_${SERF}_linux_amd64.zip
    unzip serf_${SERF}_linux_amd64.zip
  popd
fi

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
