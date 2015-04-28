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

FINAL_FILE_NAME=""

if [ "$(uname)" = "Darwin" ]; then
  PACKAGE_TYPE="osxpkg"
  LUA_MAKE="macosx"

  brew install gpg
  brew install ruby
  brew install s3cmd

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
  OPENRESTY_CONFIGURE="--with-cc-opt=-I$OUT/usr/local/include --with-ld-opt=-L$OUT/usr/local/lib"
  MKTEMP_LUAROCKS_CONF="-t rocks_config.lua"
  MKTEMP_POSTSCRIPT_CONF="-t post_install_script.sh"
  FPM_PARAMS="--osxpkg-identifier-prefix org.kong"
  FINAL_FILE_NAME="kong-$KONG_VERSION.pkg"
elif hash yum 2>/dev/null; then
  if [[ $EUID -eq 0 ]]; then
    # If already root, install sudo just in case (Docker)
    yum -y install sudo
    sed -i "s/^.*requiretty/#Defaults requiretty/" /etc/sudoers
  fi
  yum -y install epel-release
  yum -y install wget tar make curl ldconfig gcc perl pcre-devel openssl-devel ldconfig unzip git rpm-build ncurses-devel which lua-$LUA_VERSION lua-devel-$LUA_VERSION s3cmd gpg

  PACKAGE_TYPE="rpm"
  LUA_MAKE="linux"
  FPM_PARAMS="-d epel-release -d nc -d 'lua = $LUA_VERSION' -d openssl -d pcre -d openssl098e"

  CENTOS_VERSION=`cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+'`

  # Install Ruby
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
  fi

  FINAL_FILE_NAME="kong-${KONG_VERSION/-/_}.el${CENTOS_VERSION%.*}.noarch.rpm"
elif hash apt-get 2>/dev/null; then
  if [[ $EUID -eq 0 ]]; then
    # If already root, install sudo just in case (Docker)
    apt-get update && apt-get install sudo
  fi
  apt-get update && sudo apt-get -y install wget curl gnupg tar make gcc libreadline-dev libncurses5-dev libpcre3-dev libssl-dev perl unzip git lua${LUA_VERSION%.*} liblua${LUA_VERSION%.*}-0-dev s3cmd lsb-release ruby ruby-dev

  DEBIAN_VERSION=`lsb_release -cs`
  if ! [[ "$DEBIAN_VERSION" == "trusty" ]]; then
    apt-get -y install rubygems
  fi

  PACKAGE_TYPE="deb"
  LUA_MAKE="linux"
  FPM_PARAMS="-d netcat -d lua5.1 -d openssl -d libpcre3"
  FINAL_FILE_NAME="kong-$KONG_VERSION.${DEBIAN_VERSION}_all.deb"
else
  echo "Unsupported platform"
  exit 1
fi

# Find gem
GEM="gem"
if ! hash $GEM 2>/dev/null; then
  GEM=$(find / -type f -name "gem" | head -1)
fi
# Install fpm
gem install fpm

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

rocks_config=$(mktemp $MKTEMP_LUAROCKS_CONF)
echo "
rocks_trees = {
   { name = [[system]], root = [[${OUT}/usr/local]] }
}
" > $rocks_config

export LUAROCKS_CONFIG=$rocks_config
export LUA_PATH=${OUT}/usr/local/share/lua/5.1/?.lua

# Install Kong
$OUT/usr/local/bin/luarocks install kong $KONG_VERSION

# Fix the Kong bin file
sed -i.bak s@${OUT}@@g $OUT/usr/local/bin/kong
rm $OUT/usr/local/bin/kong.bak

# Copy the conf to /etc/kong
post_install_script=$(mktemp $MKTEMP_POSTSCRIPT_CONF)
echo "#!/bin/sh
sudo mkdir -p /etc/kong
sudo cp /usr/local/lib/luarocks/rocks/kong/$KONG_VERSION/conf/kong.yml /etc/kong/kong.yml" > $post_install_script

# Find fpm
FPM="fpm"
if ! hash $FPM 2>/dev/null; then
  FPM=$(find / -type f -name "fpm" | head -1)
fi

# Execute fpm
cd $OUT
eval "$FPM -a all -f -s dir -t $PACKAGE_TYPE -n 'kong' -v $KONG_VERSION $FPM_PARAMS \
--iteration 1 \
--description 'Kong is an open distributed platform for your APIs, focused on high performance and reliability.' \
--vendor Mashape \
--license MIT \
--url http://getkong.org/ \
--after-install $post_install_script \
usr"

# Save s3cmd configuration
echo "
[default]
access_key = $S3_ACCESS_KEY
acl_public = False
bucket_location = US
cloudfront_host = cloudfront.amazonaws.com
cloudfront_resource = /2008-06-30/distribution
default_mime_type = binary/octet-stream
delete_removed = False
dry_run = False
encoding = UTF-8
encrypt = False
force = False
get_continue = False
gpg_command = None
gpg_decrypt = %(gpg_command)s -d --verbose --no-use-agent --batch --yes --passphrase-fd %(passphrase_fd)s -o %(output_file)s %(input_file)s
gpg_encrypt = %(gpg_command)s -c --verbose --no-use-agent --batch --yes --passphrase-fd %(passphrase_fd)s -o %(output_file)s %(input_file)s
gpg_passphrase =
guess_mime_type = True
host_base = s3.amazonaws.com
host_bucket = %(bucket)s.s3.amazonaws.com
human_readable_sizes = False
list_md5 = False
preserve_attrs = True
progress_meter = True
proxy_host =
proxy_port = 0
recursive = False
recv_chunk = 4096
secret_key = $S3_SECRET
send_chunk = 4096
simpledb_host = sdb.amazonaws.com
skip_existing = False
urlencoding_mode = normal
use_https = False
verbosity = WARNING
" > ~/.s3cfg

# Upload file
cd $OUT
s3cmd put $(find $OUT -maxdepth 1 -type f -name "kong*.*" | head -1) s3://$S3_REPO/$FINAL_FILE_NAME

echo "DONE"