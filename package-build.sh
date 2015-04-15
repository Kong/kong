#!/bin/bash

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

echo "Current directory is: "$DIR

OUT=$DIR/build/out
TMP=$DIR/build/tmp

echo "Cleaning directories"
rm -rf $OUT
rm -rf $TMP

echo "Preparing environment"
mkdir -p $OUT
mkdir -p $TMP

LUA_VERSION=5.1.5
LUAROCKS_VERSION=2.2.1
OPENRESTY_VERSION=1.7.10.1
KONG_VERSION=0.1.1beta-2
PCRE_VERSION=8.36

PACKAGE_TYPE=""
LUA_MAKE=""
OPENRESTY_CONFIGURE=""
FPM_PARAMS=""

sudo gem install fpm

if [ "$(uname)" == "Darwin" ]; then
  PACKAGE_TYPE="osxpkg"
  LUA_MAKE="macosx"
  
  # Install PCRE
  cd $TMP
  wget ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/pcre-$PCRE_VERSION.tar.gz
  tar xzf pcre-$PCRE_VERSION.tar.gz
  cd pcre-$PCRE_VERSION
  ./configure
  make
  make install DESTDIR=$OUT
  cd $OUT

  OPENRESTY_CONFIGURE="--with-cc-opt=-I$OUT/usr/local/include --with-ld-opt=-L$OUT/usr/local/lib"
  FPM_PARAMS="--osxpkg-identifier-prefix org.getkong"
elif hash yum 2>/dev/null; then
  sudo yum -y install wget tar make gcc readline-devel perl pcre-devel openssl-devel ldconfig unzip git rpm-build ruby-devel rubygems

  PACKAGE_TYPE="rpm"
  LUA_MAKE="linux"
elif hash apt-get 2>/dev/null; then
  sudo apt-get update && sudo apt-get -y install wget tar make gcc libreadline-dev libncurses5-dev libpcre3-dev libssl-dev perl unzip git ruby-dev

  PACKAGE_TYPE="deb"
  LUA_MAKE="linux"
else
  echo "Unsupported platform"
  exit 1
fi

echo "WOT"
echo $FPM_PARAMS

# Starting building stuff

cd $TMP
wget http://www.lua.org/ftp/lua-$LUA_VERSION.tar.gz
tar xzf lua-$LUA_VERSION.tar.gz
cd lua-$LUA_VERSION
make $LUA_MAKE
make install INSTALL_TOP=$OUT/usr/local
cd $OUT

export PATH=$PATH:${OUT}/usr/local/bin
export LUA_PATH=${OUT}/usr/local/share/lua/5.1/?.lua

cd $TMP
wget http://luarocks.org/releases/luarocks-$LUAROCKS_VERSION.tar.gz
tar xzf luarocks-$LUAROCKS_VERSION.tar.gz
cd luarocks-$LUAROCKS_VERSION
./configure --with-lua-include=$OUT/usr/local/include
make build
make install DESTDIR=$OUT
cd $OUT

cd $TMP
wget ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/pcre-$PCRE_VERSION.tar.gz
tar xzf pcre-$PCRE_VERSION.tar.gz
cd $OUT

cd $TMP
wget http://openresty.org/download/ngx_openresty-$OPENRESTY_VERSION.tar.gz
tar xzf ngx_openresty-$OPENRESTY_VERSION.tar.gz
cd ngx_openresty-$OPENRESTY_VERSION
./configure --with-pcre-jit --with-ipv6 --with-http_realip_module --with-http_ssl_module --with-http_stub_status_module ${OPENRESTY_CONFIGURE}
make
make install DESTDIR=$OUT
cd $OUT

rocks_config=$(mktemp -t rocks_config.XXX.lua)
echo "
rocks_trees = {
   { name = [[system]], root = [[${OUT}/usr/local]] }
}
" > $rocks_config

export LUAROCKS_CONFIG=$rocks_config

$OUT/usr/local/bin/luarocks install kong $KONG_VERSION

# Make the package
post_install_script=$(mktemp -t post_install_script.XXX.sh)
echo "mkdir -p /etc/kong;cp /usr/local/lib/luarocks/rocks/kong/$KONG_VERSION/conf/kong.yml /etc/kong/kong.yml" > $post_install_script

cd $OUT
fpm -a all -f -s dir -t $PACKAGE_TYPE -n "kong" -v ${KONG_VERSION} ${FPM_PARAMS} \
--iteration 1 \
--description 'Kong is an open distributed platform for your APIs, focused on high performance and reliability.' \
--vendor Mashape \
--license MIT \
--url http://getkong.org/ \
--after-install $post_install_script \
usr


echo "DONE"
