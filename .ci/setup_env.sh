#!/usr/bin/env bash
set -e

#---------
# Download
#---------
OPENSSL_DOWNLOAD=$DOWNLOAD_CACHE/openssl-$OPENSSL
OPENRESTY_DOWNLOAD=$DOWNLOAD_CACHE/openresty-$OPENRESTY
OPENRESTY_PATCHES_DOWNLOAD=$DOWNLOAD_CACHE/openresty-patches-master
LUAROCKS_DOWNLOAD=$DOWNLOAD_CACHE/luarocks-$LUAROCKS
CPAN_DOWNLOAD=$DOWNLOAD_CACHE/cpanm

mkdir -p $OPENSSL_DOWNLOAD $OPENRESTY_DOWNLOAD $OPENRESTY_PATCHES_DOWNLOAD $LUAROCKS_DOWNLOAD $CPAN_DOWNLOAD

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

if [ ! "$(ls -A $OPENRESTY_PATCHES_DOWNLOAD)" ]; then
  pushd $DOWNLOAD_CACHE
    curl -s -S -L https://github.com/Kong/openresty-patches/archive/master.tar.gz | tar xz
  popd
fi

if [ ! "$(ls -A $LUAROCKS_DOWNLOAD)" ]; then
  git clone -q https://github.com/keplerproject/luarocks.git $LUAROCKS_DOWNLOAD
fi

if [ ! "$(ls -A $CPAN_DOWNLOAD)" ]; then
  wget -O $CPAN_DOWNLOAD/cpanm https://cpanmin.us
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
    echo "Installing OpenSSL $OPENSSL..."
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
    if [ -d $OPENRESTY_PATCHES_DOWNLOAD/patches/$OPENRESTY ]; then
      pushd bundle
        for patch_file in $(ls -1 $OPENRESTY_PATCHES_DOWNLOAD/patches/$OPENRESTY/*.patch); do
          echo "Applying OpenResty patch $patch_file"
          patch -p1 < $patch_file 2> build.log || (cat build.log && exit 1)
        done
      popd
    fi
    echo "Installing OpenResty $OPENRESTY..."
    ./configure ${OPENRESTY_OPTS[*]} &> build.log || (cat build.log && exit 1)
    make &> build.log || (cat build.log && exit 1)
    make install &> build.log || (cat build.log && exit 1)
  popd
fi

if [ ! "$(ls -A $LUAROCKS_INSTALL)" ]; then
  pushd $LUAROCKS_DOWNLOAD
    echo "Installing LuaRocks $LUAROCKS..."
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

export PATH=$PATH:$OPENRESTY_INSTALL/nginx/sbin:$OPENRESTY_INSTALL/bin:$LUAROCKS_INSTALL/bin:$CPAN_DOWNLOAD

eval `luarocks path`

# -------------------------------------
# Install ccm & setup Cassandra cluster
# -------------------------------------
if [[ "$TEST_SUITE" != "unit" ]] && [[ "$TEST_SUITE" != "lint" ]]; then
  echo "Installing ccm and setting up Cassandra cluster..."
  pip install --user PyYAML six ccm &> build.log || (cat build.log && exit 1)
  ccm create test -v $CASSANDRA -n 1 -d
  ccm start -v
  ccm status
fi

# -------------------
# Install Test::Nginx
# -------------------
echo "Installing CPAN dependencies..."
chmod +x $CPAN_DOWNLOAD/cpanm
cpanm --notest Test::Nginx &> build.log || (cat build.log && exit 1)
cpanm --notest --local-lib=$TRAVIS_BUILD_DIR/perl5 local::lib && eval $(perl -I $TRAVIS_BUILD_DIR/perl5/lib/perl5/ -Mlocal::lib)

nginx -V
resty -V
luarocks --version
