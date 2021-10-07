#!/usr/bin/env bash
# set -eu

dep_version() {
    grep $1 .requirements | sed -e 's/.*=//' | tr -d '\n'
}

YQ_VERSION=v4.5.0
OPENRESTY=$(dep_version RESTY_VERSION)
LUAROCKS=$(dep_version RESTY_LUAROCKS_VERSION)
OPENSSL=$(dep_version RESTY_OPENSSL_VERSION)
GO_PLUGINSERVER=$(dep_version KONG_GO_PLUGINSERVER_VERSION)
KONG_DEP_LUA_RESTY_OPENSSL_AUX_MODULE_VERSION=$(dep_version KONG_DEP_LUA_RESTY_OPENSSL_AUX_MODULE_VERSION)

DEPS_HASH=$({ cat .ci/setup_env.sh .travis.yml .requirements Makefile; cat kong-*.rockspec | awk '/dependencies/,/}/'; } | md5sum | awk '{ print $1 }')
INSTALL_CACHE=${INSTALL_CACHE:=/install-cache}
INSTALL_ROOT=$INSTALL_CACHE/$DEPS_HASH

#---------
# Prerequisite utilities
#---------
mkdir -p "$HOME"/.local/bin
export PATH=$PATH:$HOME/.local/bin

if [[ ! -e "$HOME"/.local/bin/yq ]]; then
  wget https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64 -O "$HOME"/.local/bin/yq && \
    chmod +x "$HOME"/.local/bin/yq
fi

#---------
# Download
#---------

DOWNLOAD_ROOT=${DOWNLOAD_ROOT:=/download-root}

BUILD_TOOLS_DOWNLOAD=$INSTALL_ROOT/kong-build-tools
GO_PLUGINSERVER_DOWNLOAD=$INSTALL_ROOT/go-pluginserver
LUA_RESTY_OPENSSL_AUX_MODULE_DOWNLOAD=$INSTALL_ROOT/lua-resty-openssl-aux-module

# XXX kong-ee specific, for now at least
# - Allow overriding via ENV_VAR (for CI)
# - should be set in .requirements
# - defaults to master
KONG_NGINX_MODULE_BRANCH=${KONG_NGINX_MODULE_BRANCH:-$(dep_version KONG_NGINX_MODULE_BRANCH)}
KONG_NGINX_MODULE_BRANCH=${KONG_NGINX_MODULE_BRANCH:-master}
echo "KONG_NGINX_MODULE_BRANCH: $KONG_NGINX_MODULE_BRANCH"

# XXX EE if we need a different version of build tools temporarily
#        we can set KONG_BUILD_TOOLS_BRANCH in .requirements
KONG_BUILD_TOOLS_BRANCH=${KONG_BUILD_TOOLS_BRANCH:-$(dep_version KONG_BUILD_TOOLS_BRANCH)}
KONG_BUILD_TOOLS_BRANCH=${KONG_BUILD_TOOLS_BRANCH:-$(dep_version KONG_BUILD_TOOLS_VERSION)}
KONG_BUILD_TOOLS_BRANCH=${KONG_BUILD_TOOLS_BRANCH:-master}
echo "KONG_BUILD_TOOLS_BRANCH: $KONG_BUILD_TOOLS_BRANCH"

if [ ! -d $BUILD_TOOLS_DOWNLOAD ]; then
    git clone https://github.com/Kong/kong-build-tools.git $BUILD_TOOLS_DOWNLOAD
fi

pushd $BUILD_TOOLS_DOWNLOAD
    git fetch --all
    git reset --hard $KONG_BUILD_TOOLS_BRANCH || git reset --hard origin/$KONG_BUILD_TOOLS_BRANCH
popd
export PATH=$BUILD_TOOLS_DOWNLOAD/openresty-build-tools:$PATH

if [ ! -d $GO_PLUGINSERVER_DOWNLOAD ]; then
  git clone -b $GO_PLUGINSERVER https://github.com/Kong/go-pluginserver $GO_PLUGINSERVER_DOWNLOAD
else
  pushd $GO_PLUGINSERVER_DOWNLOAD
    git fetch
    git checkout $GO_PLUGINSERVER
  popd
fi

pushd $GO_PLUGINSERVER_DOWNLOAD
  go get ./...
  make
popd

export GO_PLUGINSERVER_DOWNLOAD
export PATH=$GO_PLUGINSERVER_DOWNLOAD:$PATH

#--------
# Install
#--------

[[ -d $LUA_RESTY_OPENSSL_AUX_MODULE_DOWNLOAD ]] && rm -rf $LUA_RESTY_OPENSSL_AUX_MODULE_DOWNLOAD
git clone -b $KONG_DEP_LUA_RESTY_OPENSSL_AUX_MODULE_VERSION https://github.com/fffonion/lua-resty-openssl-aux-module $LUA_RESTY_OPENSSL_AUX_MODULE_DOWNLOAD

export NGX_LUA_LOC="$DOWNLOAD_ROOT/openresty-*/build/ngx_lua-*"

echo kong-ngx-build \
    --work $DOWNLOAD_ROOT \
    --prefix $INSTALL_ROOT \
    --openresty $OPENRESTY \
    --kong-nginx-module $KONG_NGINX_MODULE_BRANCH \
    --luarocks $LUAROCKS \
    --openssl $OPENSSL \
    --debug \
    --add-module $LUA_RESTY_OPENSSL_AUX_MODULE_DOWNLOAD \
    -j $JOBS

# XXX Some versions of kong-ngx-build grok at having no EDITION set, always
# use test2 or quote envs
EDITION=""
kong-ngx-build \
    --work $DOWNLOAD_ROOT \
    --prefix $INSTALL_ROOT \
    --openresty $OPENRESTY \
    --kong-nginx-module $KONG_NGINX_MODULE_BRANCH \
    --luarocks $LUAROCKS \
    --openssl $OPENSSL \
    --debug \
    --add-module $LUA_RESTY_OPENSSL_AUX_MODULE_DOWNLOAD \
    -j $JOBS

pushd $LUA_RESTY_OPENSSL_AUX_MODULE_DOWNLOAD
  make install LUA_LIB_DIR=$INSTALL_ROOT/openresty/lualib
popd

OPENSSL_INSTALL=$INSTALL_ROOT/openssl
OPENRESTY_INSTALL=$INSTALL_ROOT/openresty
LUAROCKS_INSTALL=$INSTALL_ROOT/luarocks

export OPENSSL_DIR=$OPENSSL_INSTALL # for LuaSec install

export PATH=$OPENSSL_INSTALL/bin:$OPENRESTY_INSTALL/nginx/sbin:$OPENRESTY_INSTALL/bin:$LUAROCKS_INSTALL/bin:$PATH
export LD_LIBRARY_PATH=$OPENSSL_INSTALL/lib:$LD_LIBRARY_PATH # for openssl's CLI invoked in the test suite


eval `luarocks path`

# -------------------------------------
# Install ccm & setup Cassandra cluster
# -------------------------------------
if [[ "$KONG_TEST_DATABASE" == "cassandra" ]]; then
  echo "Setting up Cassandra"
  docker run -d --name=cassandra --rm -p 7199:7199 -p 7000:7000 -p 9160:9160 -p 9042:9042 cassandra:$CASSANDRA
  grep -q 'Created default superuser role' <(docker logs -f cassandra)
# -------------------------------------
# Setup Postgres
# -------------------------------------
elif  [ "$KONG_TEST_DATABASE" == "postgres" ]; then
  PG_DB=${KONG_TEST_PG_DATABASE:-kong_tests}
  PG_USER=${KONG_TEST_PG_USER:-kong}
  PG_PASS=${KONG_TEST_PG_PASSWORD:-kong}
  echo "Setting up Postgres $POSTGRES db $PG_DB with auth $PG_USER:$PG_PASS"
  docker run -d --name=postgres --rm -p 5432:5432 -e POSTGRES_USER=$PG_USER \
  -e POSTGRES_PASSWORD=$PG_PASS -e POSTGRES_HOST_AUTH_METHOD=trust \
  -e POSTGRES_DB=$PG_DB postgres:$POSTGRES
fi

# -------------------
# Install Test::Nginx
# -------------------
if [[ "$TEST_SUITE" == "pdk" ]]; then
  CPAN_DOWNLOAD=$DOWNLOAD_ROOT/cpanm
  mkdir -p $CPAN_DOWNLOAD
  curl -o $CPAN_DOWNLOAD/cpanm https://cpanmin.us
  chmod +x $CPAN_DOWNLOAD/cpanm
  export PATH=$CPAN_DOWNLOAD:$PATH

  echo "Installing CPAN dependencies..."
  cpanm --notest Test::Nginx &> build.log || (cat build.log && exit 1)
  cpanm --notest --local-lib=$TRAVIS_BUILD_DIR/perl5 local::lib && eval $(perl -I $TRAVIS_BUILD_DIR/perl5/lib/perl5/ -Mlocal::lib)
fi

# ------------------------------------
# Install additional test dependencies
# ------------------------------------
go get -u github.com/tsenart/vegeta
vegeta -version

# ---------------
# Run gRPC server
# ---------------
if [[ "$TEST_SUITE" =~ integration|dbless|plugins ]]; then
  docker run -d --name grpcbin -p 15002:9000 -p 15003:9001 moul/grpcbin
fi

# ------------------------------------
# Install additional test dependencies
# ------------------------------------
git clone --branch $(dep_version KONG_PGMOON_VERSION) https://github.com/Kong/pgmoon/
pushd pgmoon
luarocks make
popd
rm -rf pgmoon

nginx -V
resty -V
luarocks --version
openssl version
