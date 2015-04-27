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
MKTEMP_LUAROCKS_CONF=""
MKTEMP_POSTSCRIPT_CONF=""
LUA_MAKE=""
OPENRESTY_CONFIGURE=""
LUAROCKS_CONFIGURE=""
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

  export PATH=$PATH:${OUT}/usr/local/bin

  LUAROCKS_CONFIGURE="--with-lua-include=$OUT/usr/local/include"
  RUBY_CONFIGURE="--with-openssl-dir=/usr/local/ssl"
  OPENRESTY_CONFIGURE="--with-cc-opt=-I$OUT/usr/local/include --with-ld-opt=-L$OUT/usr/local/lib"
  MKTEMP_LUAROCKS_CONF="-t rocks_config.lua"
  MKTEMP_POSTSCRIPT_CONF="-t post_install_script.XXX.sh"
  FPM_PARAMS="--osxpkg-identifier-prefix org.kong"
elif hash yum 2>/dev/null; then
  if [[ $EUID -eq 0 ]]; then
    # If already root, install sudo just in case (Docker)
    yum -y install sudo
    sed -i "s/^.*requiretty/#Defaults requiretty/" /etc/sudoers
  fi
  sudo yum -y install epel-release
  sudo yum -y install wget tar make ldconfig gcc perl pcre-devel openssl-devel-0.9.8e ldconfig unzip git rpm-build ncurses-devel which lua-$LUA_VERSION lua-devel-$LUA_VERSION

  PACKAGE_TYPE="rpm"
  LUA_MAKE="linux"
  FPM_PARAMS="-d epel-release -d nc -d 'lua = $LUA_VERSION' -d openssl098e"
elif hash apt-get 2>/dev/null; then
  if [[ $EUID -eq 0 ]]; then
    # If already root, install sudo just in case (Docker)
    apt-get update && apt-get install sudo
  fi
  sudo apt-get update && sudo apt-get -y install wget tar make gcc libreadline-dev libncurses5-dev libpcre3-dev libssl-dev=0.9.8* perl unzip git lua${LUA_VERSION%.*}=$LUA_VERSION* liblua${LUA_VERSION%.*}-0-dev=$LUA_VERSION*

  PACKAGE_TYPE="deb"
  LUA_MAKE="linux"
  FPM_PARAMS="-d netcat -d lua5.1 -d libssl0.9.8"
else
  echo "Unsupported platform"
  exit 1
fi

# This is required on the building machine
MATCH_STR="ruby $RUBY_VERSION"
if ! [[ `ruby -v` == $MATCH_STR* ]]; then
  cd $TMP
  wget http://cache.ruby-lang.org/pub/ruby/${RUBY_VERSION%.*}/ruby-$RUBY_VERSION.tar.gz
  tar xvfvz ruby-$RUBY_VERSION.tar.gz
  cd ruby-$RUBY_VERSION
  ./configure $RUBY_CONFIGURE
  make
  sudo make install

  sudo gem update --system
  sudo gem install fpm
fi

# Starting building software (included in the package)
cd $TMP
wget http://openresty.org/download/ngx_openresty-$OPENRESTY_VERSION.tar.gz
tar xzf ngx_openresty-$OPENRESTY_VERSION.tar.gz
cd ngx_openresty-$OPENRESTY_VERSION
./configure --with-pcre-jit --with-ipv6 --with-http_realip_module --with-http_ssl_module --with-http_stub_status_module ${OPENRESTY_CONFIGURE}
make
make install DESTDIR=$OUT
cd $OUT

cd $TMP
wget http://luarocks.org/releases/luarocks-$LUAROCKS_VERSION.tar.gz
tar xzf luarocks-$LUAROCKS_VERSION.tar.gz
cd luarocks-$LUAROCKS_VERSION
./configure $LUAROCKS_CONFIGURE
make build
make install DESTDIR=$OUT
cd $OUT

#rocks_config=$(mktemp $MKTEMP_LUAROCKS_CONF)
#echo "
#rocks_trees = {
#   { name = [[system]], root = [[${OUT}/usr/local]] }
#}
#" > $rocks_config

#export LUAROCKS_CONFIG=$rocks_config
#export LUA_PATH=${OUT}/usr/local/share/lua/5.1/?.lua

# Install Kong
#$OUT/usr/local/bin/luarocks install kong $KONG_VERSION

# Fix the Kong bin file
#sed -i.bak s@${OUT}@@g $OUT/usr/local/bin/kong
#rm $OUT/usr/local/bin/kong.bak

cd $TMP
git clone --branch $KONG_VERSION https://github.com/Mashape/kong.git
cd kong
luarocks pack kong-$KONG_VERSION.rockspec
mkdir -p $OUT/usr/local/kong
cp kong-$KONG_VERSION.src.rock $OUT/usr/local/kong/
cd $OUT

# Copy the conf to /etc/kong
post_install_script=$(mktemp $MKTEMP_POSTSCRIPT_CONF)
echo "#!/bin/sh
sudo /usr/local/bin/luarocks install /usr/local/kong/kong-$KONG_VERSION.src.rock
sudo rm /usr/local/kong/kong-$KONG_VERSION.src.rock
sudo mkdir -p /etc/kong
sudo cp /usr/local/lib/luarocks/rocks/kong/$KONG_VERSION/conf/kong.yml /etc/kong/kong.yml
" > $post_install_script

cd $OUT

eval "fpm -a all -f -s dir -t $PACKAGE_TYPE -n 'kong' -v $KONG_VERSION $FPM_PARAMS \
--iteration 1 \
--description 'Kong is an open distributed platform for your APIs, focused on high performance and reliability.' \
--vendor Mashape \
--license MIT \
--url http://getkong.org/ \
--after-install $post_install_script \
usr"

echo "DONE"