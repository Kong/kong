OUT=/tmp/build/out
TMP=/tmp/build/tmp
echo "Cleaning directories"
rm -rf $OUT
rm -rf $TMP
echo "Preparing environment"
mkdir -p $OUT
mkdir -p $TMP

OPENSSL_VERSION=1.0.2d
OPENRESTY_VERSION=1.7.10.2
OPENRESTY_CONFIGURE=""


# Download OpenSSL
cd $TMP
wget -q https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz -O openssl-$OPENSSL_VERSION.tar.gz 
tar xzf openssl-$OPENSSL_VERSION.tar.gz
if [ "$(uname)" = "Darwin" ]; then # Checking if OS X
  export KERNEL_BITS=64 # This sets the right OpenSSL variable for OS X
fi
OPENRESTY_CONFIGURE="--with-openssl=$TMP/openssl-$OPENSSL_VERSION"


############################################
######### Install Patched OpenResty ########
############################################
cd $TMP
wget -q http://openresty.org/download/ngx_openresty-$OPENRESTY_VERSION.tar.gz
tar xzf ngx_openresty-$OPENRESTY_VERSION.tar.gz
cd ngx_openresty-$OPENRESTY_VERSION
# Download and apply nginx patch
cd bundle/nginx-*
wget -q https://raw.githubusercontent.com/openresty/lua-nginx-module/ssl-cert-by-lua/patches/nginx-ssl-cert.patch --no-check-certificate
patch -p1 < nginx-ssl-cert.patch
cd ..
# Download `ssl-cert-by-lua` branch
wget -q https://github.com/openresty/lua-nginx-module/archive/ssl-cert-by-lua.tar.gz -O ssl-cert-by-lua.tar.gz --no-check-certificate
tar xzf ssl-cert-by-lua.tar.gz
# Replace `ngx_lua-*` with `ssl-cert-by-lua` branch
NGX_LUA=`ls | grep ngx_lua-*`
rm -rf $NGX_LUA
mv lua-nginx-module-ssl-cert-by-lua $NGX_LUA
# Configure and install
cd $TMP/ngx_openresty-$OPENRESTY_VERSION
./configure --with-pcre-jit --with-ipv6 --with-http_realip_module --with-http_ssl_module --with-http_stub_status_module ${OPENRESTY_CONFIGURE}
make
make install