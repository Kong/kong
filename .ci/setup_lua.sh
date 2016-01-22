#!/bin/bash

# A script for setting up environment for travis-ci testing.
# Sets up Lua and Luarocks.
# LUA must be "lua5.1", "lua5.2" or "luajit".
# luajit2.0 - master v2.0
# luajit2.1 - master v2.1

set -e

LUAJIT="no"

source .ci/platform.sh

############
# Lua/LuaJIT
############

if [ "$LUA_VERSION" == "luajit" ]; then
  LUAJIT="yes"
  LUA_VERSION="luajit-2.0"
elif [ "$LUA_VERSION" == "luajit-2.0" ]; then
  LUAJIT="yes"
elif [ "$LUA_VERSION" == "luajit-2.1" ]; then
  LUAJIT="yes"
fi

if [ "$LUAJIT" == "yes" ]; then
  mkdir -p $LUAJIT_DIR

  # If cache is empty, download and compile
  if [ ! "$(ls -A $LUAJIT_DIR)" ]; then
    git clone https://github.com/luajit/luajit $LUAJIT_DIR
    pushd $LUAJIT_DIR

    if [ "$LUA_VERSION" == "luajit-2.0" ]; then
      git checkout v2.0.4
    elif [ "$LUA_VERSION" == "luajit-2.1" ]; then
      git checkout v2.1
    fi

    make
    make install PREFIX=$LUAJIT_DIR
    popd

    if [ "$LUA_VERSION" == "luajit-2.1" ]; then
      ln -sf $LUAJIT_DIR/bin/luajit-2.1.0-beta1 $LUAJIT_DIR/bin/luajit
    fi

    ln -sf $LUAJIT_DIR/bin/luajit $LUAJIT_DIR/bin/lua
  fi

  LUA_INCLUDE="$LUAJIT_DIR/include/$LUA_VERSION"
else
  if [ "$LUA_VERSION" == "lua5.1" ]; then
    curl http://www.lua.org/ftp/lua-5.1.5.tar.gz | tar xz
    pushd lua-5.1.5
  elif [ "$LUA_VERSION" == "lua5.2" ]; then
    curl http://www.lua.org/ftp/lua-5.2.3.tar.gz | tar xz
    pushd lua-5.2.3
  elif [ "$LUA_VERSION" == "lua5.3" ]; then
    curl http://www.lua.org/ftp/lua-5.3.0.tar.gz | tar xz
    pushd lua-5.3.0
  fi

  make $PLATFORM
  make install INSTALL_TOP=$LUA_DIR
  popd

  LUA_INCLUDE="$LUA_DIR/include"
fi

##########
# Luarocks
##########

LUAROCKS_BASE=luarocks-$LUAROCKS_VERSION
CONFIGURE_FLAGS=""

git clone https://github.com/keplerproject/luarocks.git $LUAROCKS_BASE

pushd $LUAROCKS_BASE
git checkout v$LUAROCKS_VERSION

if [ "$LUAJIT" == "yes" ]; then
  LUA_DIR=$LUAJIT_DIR
elif [ "$LUA_VERSION" == "lua5.1" ]; then
  CONFIGURE_FLAGS=$CONFIGURE_FLAGS" --lua-version=5.1"
elif [ "$LUA_VERSION" == "lua5.2" ]; then
  CONFIGURE_FLAGS=$CONFIGURE_FLAGS" --lua-version=5.2"
elif [ "$LUA_VERSION" == "lua5.3" ]; then
  CONFIGURE_FLAGS=$CONFIGURE_FLAGS" --lua-version=5.3"
fi

./configure \
  --prefix=$LUAROCKS_DIR \
  --with-lua-bin=$LUA_DIR/bin \
  --with-lua-include=$LUA_INCLUDE \
  $CONFIGURE_FLAGS

make build && make install
popd
