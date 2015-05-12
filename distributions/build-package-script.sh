#!/bin/bash

set -o errexit

# Check Kong version
if [ -z "$1" ]; then
  echo "Specify a Kong version"
  exit 1
fi
KONG_BRANCH=$1

# Preparing environment
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
echo "Current directory is: "$DIR
if [ "$DIR" == "/" ]; then
  DIR=""
fi
OUT=/tmp/build/out
TMP=/tmp/build/tmp
echo "Cleaning directories"
rm -rf $OUT
rm -rf $TMP
echo "Preparing environment"
mkdir -p $OUT
mkdir -p $TMP

# Load dependencies versions
LUA_VERSION=5.1.4
PCRE_VERSION=8.36
LUAROCKS_VERSION=2.2.2
OPENRESTY_VERSION=1.7.10.2rc0
DNSMASQ_VERSION=2.72

# Variables to be used in the build process
PACKAGE_TYPE=""
MKTEMP_LUAROCKS_CONF=""
MKTEMP_POSTSCRIPT_CONF=""
LUA_MAKE=""
OPENRESTY_CONFIGURE=""
LUAROCKS_CONFIGURE=""
FPM_PARAMS=""
FINAL_FILE_NAME=""

FINAL_BUILD_OUTPUT="/build-data/build-output"

if [ "$(uname)" = "Darwin" ]; then
  brew install gpg
  brew install ruby

  PACKAGE_TYPE="osxpkg"
  LUA_MAKE="macosx"
  MKTEMP_LUAROCKS_CONF="-t rocks_config.lua"
  MKTEMP_POSTSCRIPT_CONF="-t post_install_script.sh"
  FPM_PARAMS="--osxpkg-identifier-prefix org.kong"
  FINAL_FILE_NAME_SUFFIX=".pkg"

  FINAL_BUILD_OUTPUT="$DIR/build-output"
elif hash yum 2>/dev/null; then
  yum -y install epel-release
  yum -y install wget tar make curl ldconfig gcc perl pcre-devel openssl-devel ldconfig unzip git rpm-build ncurses-devel which lua-$LUA_VERSION lua-devel-$LUA_VERSION gpg

  CENTOS_VERSION=`cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+'`
  FPM_PARAMS="-d 'epel-release' -d 'sudo' -d 'nc' -d 'lua = $LUA_VERSION' -d 'openssl' -d 'pcre' -d 'dnsmasq'"

  # Install Ruby for fpm
  if [[ ${CENTOS_VERSION%.*} == "5" ]]; then
    cd $TMP
    wget http://cache.ruby-lang.org/pub/ruby/2.2/ruby-2.2.2.tar.gz
    tar xvfvz ruby-2.2.2.tar.gz
    cd ruby-2.2.2
    ./configure
    make
    make install
    gem update --system
  else
    yum -y install ruby ruby-devel rubygems
    FPM_PARAMS=$FPM_PARAMS" -d 'openssl098e'"
  fi

  PACKAGE_TYPE="rpm"
  LUA_MAKE="linux"
  FINAL_FILE_NAME_SUFFIX=".el${CENTOS_VERSION%.*}.noarch.rpm"
elif hash apt-get 2>/dev/null; then
  apt-get update && apt-get -y install wget curl gnupg tar make gcc libreadline-dev libncurses5-dev libpcre3-dev libssl-dev perl unzip git lua${LUA_VERSION%.*} liblua${LUA_VERSION%.*}-0-dev lsb-release ruby ruby-dev

  DEBIAN_VERSION=`lsb_release -cs`
  if ! [[ "$DEBIAN_VERSION" == "trusty" ]]; then
    apt-get -y install rubygems
  fi

  PACKAGE_TYPE="deb"
  LUA_MAKE="linux"
  FPM_PARAMS="-d 'netcat' -d 'sudo' -d 'lua5.1' -d 'openssl' -d 'libpcre3' -d 'dnsmasq'"
  FINAL_FILE_NAME_SUFFIX=".${DEBIAN_VERSION}_all.deb"
else
  echo "Unsupported platform"
  exit 1
fi

export PATH=$PATH:${OUT}/usr/local/bin:$(gem environment | awk -F': *' '/EXECUTABLE DIRECTORY/ {print $2}')

# Check if the Kong version exists
if ! [ `curl -s -o /dev/null -w "%{http_code}" https://github.com/Mashape/kong/tree/$KONG_BRANCH` == "200" ]; then
  echo "Kong version \"$KONG_BRANCH\" doesn't exist!"
  exit 1
else
  echo "Building Kong: $KONG_BRANCH"
fi

# Install fpm
gem install fpm

##############################################################
# Starting building software (to be included in the package) #
##############################################################

if [ "$(uname)" = "Darwin" ]; then
  # Install PCRE
  cd $TMP
  wget ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/pcre-$PCRE_VERSION.tar.gz
  tar xzf pcre-$PCRE_VERSION.tar.gz
  cd pcre-$PCRE_VERSION
  ./configure
  make
  make install DESTDIR=$OUT
  cd $OUT

  # Install Lua
  cd $TMP
  wget http://www.lua.org/ftp/lua-$LUA_VERSION.tar.gz
  tar xzf lua-$LUA_VERSION.tar.gz
  cd lua-$LUA_VERSION
  make $LUA_MAKE
  make install INSTALL_TOP=$OUT/usr/local
  cd $OUT

  # Install dnsmasq
  cd $TMP
  wget http://www.thekelleys.org.uk/dnsmasq/dnsmasq-$DNSMASQ_VERSION.tar.gz
  tar xzf dnsmasq-$DNSMASQ_VERSION.tar.gz
  cd dnsmasq-$DNSMASQ_VERSION
  make
  make install DESTDIR=$OUT
  cd $OUT

  LUAROCKS_CONFIGURE="--with-lua-include=$OUT/usr/local/include"
  OPENRESTY_CONFIGURE="--with-cc-opt=-I$OUT/usr/local/include --with-ld-opt=-L$OUT/usr/local/lib"
fi

# Install OpenResty
cd $TMP
wget http://openresty.org/download/ngx_openresty-$OPENRESTY_VERSION.tar.gz
tar xzf ngx_openresty-$OPENRESTY_VERSION.tar.gz
cd ngx_openresty-$OPENRESTY_VERSION
./configure --with-pcre-jit --with-ipv6 --with-http_realip_module --with-http_ssl_module --with-http_stub_status_module ${OPENRESTY_CONFIGURE}
make
make install DESTDIR=$OUT
cd $OUT

# Install LuaRocks
cd $TMP
wget http://luarocks.org/releases/luarocks-$LUAROCKS_VERSION.tar.gz
tar xzf luarocks-$LUAROCKS_VERSION.tar.gz
cd luarocks-$LUAROCKS_VERSION
./configure $LUAROCKS_CONFIGURE
make build
make install DESTDIR=$OUT
cd $OUT

# Configure LuaRocks
rocks_config=$(mktemp $MKTEMP_LUAROCKS_CONF)
echo "
rocks_trees = {
   { name = [[system]], root = [[${OUT}/usr/local]] }
}
" > $rocks_config
export LUAROCKS_CONFIG=$rocks_config
export LUA_PATH=${OUT}/usr/local/share/lua/5.1/?.lua

# Install Kong
cd $TMP
git clone --branch $KONG_BRANCH --depth 1 https://github.com/Mashape/kong.git
cd kong
$OUT/usr/local/bin/luarocks make kong-*.rockspec

# Extract the version from the rockspec file
rockspec_filename=`basename $TMP/kong/kong-*.rockspec`
rockspec_basename=${rockspec_filename%.*}
rockspec_version=${rockspec_basename#"kong-"}

# Fix the Kong bin file
sed -i.bak s@${OUT}@@g $OUT/usr/local/bin/kong
rm $OUT/usr/local/bin/kong.bak

# Copy the conf to /etc/kong
post_install_script=$(mktemp $MKTEMP_POSTSCRIPT_CONF)
echo "#!/bin/sh
mkdir -p /etc/kong
cp /usr/local/lib/luarocks/rocks/kong/$rockspec_version/conf/kong.yml /etc/kong/kong.yml
echo \"user=root\" > /etc/dnsmasq.conf" > $post_install_script

##############################################################
#                      Build the package                     #
##############################################################

# Build proper version
initial_letter="$(echo $KONG_BRANCH | head -c 1)"
re='^[0-9]+$' # to check it's a number
if ! [[ $initial_letter =~ $re ]] ; then
  KONG_VERSION="${rockspec_version%-*}$KONG_BRANCH"
elif [ $PACKAGE_TYPE == "rpm" ]; then
  KONG_VERSION=${KONG_BRANCH//-/_}
else
  KONG_VERSION=$KONG_BRANCH
fi

# Execute fpm
cd $OUT
eval "fpm -a all -f -s dir -t $PACKAGE_TYPE -n 'kong' -v $KONG_VERSION $FPM_PARAMS \
--description 'Kong is an open distributed platform for your APIs, focused on high performance and reliability.' \
--vendor Mashape \
--license MIT \
--url http://getkong.org/ \
--after-install $post_install_script \
usr"

# Copy file to host
mkdir -p $FINAL_BUILD_OUTPUT
cp $(find $OUT -maxdepth 1 -type f -name "kong*.*" | head -1) $FINAL_BUILD_OUTPUT/kong-$KONG_VERSION$FINAL_FILE_NAME_SUFFIX

echo "DONE"