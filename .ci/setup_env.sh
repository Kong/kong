#!/usr/bin/env bash
set -e

#---------
# Download
#---------

DEPS_HASH=$(cat .ci/setup_env.sh .travis.yml | md5sum | awk '{ print $1 }')

OPENSSL_DOWNLOAD=$DOWNLOAD_CACHE/$DEPS_HASH/openssl-$OPENSSL
OPENRESTY_DOWNLOAD=$DOWNLOAD_CACHE/$DEPS_HASH/openresty-$OPENRESTY
OPENRESTY_PATCHES_DOWNLOAD=$DOWNLOAD_CACHE/$DEPS_HASH/openresty-patches-master
LUAROCKS_DOWNLOAD=$DOWNLOAD_CACHE/$DEPS_HASH/luarocks-$LUAROCKS
CPAN_DOWNLOAD=$DOWNLOAD_CACHE/$DEPS_HASH/cpanm

mkdir -p $OPENSSL_DOWNLOAD $OPENRESTY_DOWNLOAD $OPENRESTY_PATCHES_DOWNLOAD $LUAROCKS_DOWNLOAD $CPAN_DOWNLOAD

if [ ! "$(ls -A $OPENSSL_DOWNLOAD)" ]; then
  pushd $DOWNLOAD_CACHE/$DEPS_HASH
    curl -s -S -L http://www.openssl.org/source/openssl-$OPENSSL.tar.gz | tar xz
  popd
fi

if [ ! "$(ls -A $OPENRESTY_DOWNLOAD)" ]; then
  pushd $DOWNLOAD_CACHE/$DEPS_HASH
    curl -s -S -L https://openresty.org/download/openresty-$OPENRESTY.tar.gz | tar xz
  popd
fi

if [ ! "$(ls -A $OPENRESTY_PATCHES_DOWNLOAD)" ]; then
  pushd $DOWNLOAD_CACHE/$DEPS_HASH
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
OPENSSL_INSTALL=$INSTALL_CACHE/$DEPS_HASH/openssl-$OPENSSL
OPENRESTY_INSTALL=$INSTALL_CACHE/$DEPS_HASH/openresty-$OPENRESTY
LUAROCKS_INSTALL=$INSTALL_CACHE/$DEPS_HASH/luarocks-$LUAROCKS

mkdir -p $OPENSSL_INSTALL $OPENRESTY_INSTALL $LUAROCKS_INSTALL

if [ ! "$(ls -A $OPENSSL_INSTALL)" ]; then
  pushd $OPENSSL_DOWNLOAD
    echo "Installing OpenSSL $OPENSSL..."
    ./config shared --prefix=$OPENSSL_INSTALL &> build.log || (cat build.log && exit 1)
    make &> build.log || (cat build.log && exit 1)
    make install_sw &> build.log || (cat build.log && exit 1)
  popd
fi

if [ ! "$(ls -A $OPENRESTY_INSTALL)" ]; then
  OPENRESTY_OPTS=(
    "--prefix=$OPENRESTY_INSTALL"
    "--with-cc-opt='-I$OPENSSL_INSTALL/include'"
    "--with-ld-opt='-L$OPENSSL_INSTALL/lib -Wl,-rpath,$OPENSSL_INSTALL/lib'"
    "--with-pcre-jit"
    "--with-http_ssl_module"
    "--with-http_realip_module"
    "--with-http_stub_status_module"
    "--with-http_v2_module"
    "--with-stream_ssl_preread_module"
    "--with-stream_realip_module"
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
    eval ./configure ${OPENRESTY_OPTS[*]} &> build.log || (cat build.log && exit 1)
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

export PATH=$OPENSSL_INSTALL/bin:$OPENRESTY_INSTALL/nginx/sbin:$OPENRESTY_INSTALL/bin:$LUAROCKS_INSTALL/bin:$CPAN_DOWNLOAD:$PATH
export LD_LIBRARY_PATH=$OPENSSL_INSTALL/lib:$LD_LIBRARY_PATH # for openssl's CLI invoked in the test suite

eval `luarocks path`

# -------------------------------------
# Install ccm & setup Cassandra cluster
# -------------------------------------
if [[ "$KONG_TEST_DATABASE" == "cassandra" ]]; then
  echo "Setting up Cassandra"
  docker run -d --name=cassandra --rm -p 7199:7199 -p 7000:7000 -p 9160:9160 -p 9042:9042 cassandra:$CASSANDRA
  grep -q 'Created default superuser role' <(docker logs -f cassandra)
fi

# -------------------
# Install Test::Nginx
# -------------------
if [[ "$TEST_SUITE" == "pdk" ]]; then
  echo "Installing CPAN dependencies..."
  chmod +x $CPAN_DOWNLOAD/cpanm
  cpanm --notest Test::Nginx &> build.log || (cat build.log && exit 1)
  cpanm --notest --local-lib=$TRAVIS_BUILD_DIR/perl5 local::lib && eval $(perl -I $TRAVIS_BUILD_DIR/perl5/lib/perl5/ -Mlocal::lib)
fi

nginx -V
resty -V
luarocks --version
openssl version
