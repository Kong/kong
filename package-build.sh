#!/bin/bash

# Create "pkg": wget https://raw.githubusercontent.com/Mashape/kong/master/versions.sh --no-check-certificate && wget -O - https://raw.githubusercontent.com/Mashape/kong/master/package-build.sh --no-check-certificate | /bin/bash
# Create "rpm": docker run centos:5 /bin/bash -c "yum -y install wget && wget https://raw.githubusercontent.com/Mashape/kong/master/versions.sh --no-check-certificate && wget -O - https://raw.githubusercontent.com/Mashape/kong/master/package-build.sh --no-check-certificate | /bin/bash"
# Create "deb": docker run debian:6 /bin/bash -c "apt-get update && apt-get -y install wget && wget https://raw.githubusercontent.com/Mashape/kong/master/versions.sh --no-check-certificate && wget -O - https://raw.githubusercontent.com/Mashape/kong/master/package-build.sh --no-check-certificate | /bin/bash"

set -o errexit

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

echo "Current directory is: "$DIR

if [ "$DIR" == "/" ]; then
  DIR=""
fi

OUT=$DIR/build/out
TMP=$DIR/build/tmp

echo "Cleaning directories"
rm -rf $OUT
rm -rf $TMP

echo "Preparing environment"
mkdir -p $OUT
mkdir -p $TMP

# Load dependencies versions
source ./versions.sh

PACKAGE_TYPE=""
LUA_MAKE=""
OPENRESTY_CONFIGURE=""
LUAROCKS_CONFIGURE=""
LUAROCKS_ROOT="/usr/local"
FPM_PARAMS=""
RUBY_CONFIGURE=""

if [ "$(uname)" = "Darwin" ]; then
  PACKAGE_TYPE="osxpkg"
  LUA_MAKE="macosx"

  # Install OpenSSL
  cd $TMP
  wget https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz
  tar xzf openssl-$OPENSSL_VERSION.tar.gz
  cd openssl-$OPENSSL_VERSION
  ./Configure darwin64-x86_64-cc
  make
  sudo make install
  cd $OUT

  # Install PCRE (included in the package)
  cd $TMP
  wget ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/pcre-$PCRE_VERSION.tar.gz
  tar xzf pcre-$PCRE_VERSION.tar.gz
  cd pcre-$PCRE_VERSION
  ./configure
  make
  make install DESTDIR=$OUT
  cd $OUT

  # Install Lua (included in the package)
  cd $TMP
  wget http://www.lua.org/ftp/lua-$LUA_VERSION.tar.gz
  tar xzf lua-$LUA_VERSION.tar.gz
  cd lua-$LUA_VERSION
  make $LUA_MAKE
  make install INSTALL_TOP=$OUT/usr/local
  cd $OUT

  LUAROCKS_ROOT="${OUT}/usr/local"

  export PATH=$PATH:${OUT}/usr/local/bin
  export LUA_PATH=${OUT}/usr/local/share/lua/5.1/?.lua

  LUAROCKS_CONFIGURE="--with-lua-include=$OUT/usr/local/include"
  RUBY_CONFIGURE="--with-openssl-dir=/usr/local/ssl"
  OPENRESTY_CONFIGURE="--with-cc-opt=-I$OUT/usr/local/include --with-ld-opt=-L$OUT/usr/local/lib"
  FPM_PARAMS="--osxpkg-identifier-prefix org.kong"
elif hash yum 2>/dev/null; then
  if [[ $EUID -eq 0 ]]; then
    # If already root, install sudo just in case (Docker)
    yum -y install sudo
    sed -i "s/^.*requiretty/#Defaults requiretty/" /etc/sudoers
  fi
  sudo yum -y install epel-release
  sudo yum -y install wget tar make ldconfig gcc perl pcre-devel openssl-devel ldconfig unzip git rpm-build ncurses-devel which lua-$LUA_VERSION lua-devel-$LUA_VERSION

  PACKAGE_TYPE="rpm"
  LUA_MAKE="linux"
  FPM_PARAMS="-d nc -d lua-$LUA_VERSION"
elif hash apt-get 2>/dev/null; then
  if [[ $EUID -eq 0 ]]; then
    # If already root, install sudo just in case (Docker)
    apt-get update && apt-get install sudo
  fi
  sudo apt-get update && sudo apt-get -y install wget tar make gcc libreadline-dev libncurses5-dev libpcre3-dev libssl-dev perl unzip git lua5.1=$LUA_VERSION* liblua5.1-0-dev=$LUA_VERSION*

  PACKAGE_TYPE="deb"
  LUA_MAKE="linux"
  FPM_PARAMS="-d netcat -d lua5.1=$LUA_VERSION*"
else
  echo "Unsupported platform"
  exit 1
fi

# This is required on the building machine
cd $TMP
wget http://cache.ruby-lang.org/pub/ruby/2.2/ruby-2.2.2.tar.gz
tar xvfvz ruby-2.2.2.tar.gz
cd ruby-2.2.2
./configure $RUBY_CONFIGURE
make
sudo make install

sudo gem update --system
sudo gem install fpm

# Starting building software (included in the package)
cd $TMP
wget http://luarocks.org/releases/luarocks-$LUAROCKS_VERSION.tar.gz
tar xzf luarocks-$LUAROCKS_VERSION.tar.gz
cd luarocks-$LUAROCKS_VERSION
./configure $LUAROCKS_CONFIGURE
make build
make install DESTDIR=$OUT
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
   { name = [[system]], root = [[${LUAROCKS_ROOT}]] }
}
" > $rocks_config

export LUAROCKS_CONFIG=$rocks_config

# Install Kong
$OUT/usr/local/bin/luarocks install kong $KONG_VERSION

# Fix the Kong bin file
sed -i.bak s@${OUT}@@g $OUT/usr/local/bin/kong
rm $OUT/usr/local/bin/kong.bak

# Copy the conf to /etc/kong
mkdir -p $OUT/etc/kong
cp $OUT/usr/local/lib/luarocks/rocks/kong/$KONG_VERSION/conf/kong.yml $OUT/etc/kong/kong.yml

# Make the package
post_install_script=$(mktemp -t post_install_script.XXX.sh)
printf "#!/bin/sh\nsudo mkdir -p /etc/kong\nsudo cp /usr/local/lib/luarocks/rocks/kong/$KONG_VERSION/conf/kong.yml /etc/kong/kong.yml" > $post_install_script

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
