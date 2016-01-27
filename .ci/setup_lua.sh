#!/bin/bash

set -e

mkdir -p $LUA_DIR
if [ "$(ls -A $LUA_DIR)" ]; then
  echo "Lua found from cache at $LUA_DIR"
  exit
fi

LUAJIT="no"
LUAJIT_BASE="LuaJIT"

source .ci/platform.sh

############
# Lua/LuaJIT
############

if [ "$LUA" == "luajit" ]; then
  LUAJIT="yes"
  LUA="luajit-2.0"
elif [ "$LUA" == "luajit-2.0" ]; then
  LUAJIT="yes"
elif [ "$LUA" == "luajit-2.1" ]; then
  LUAJIT="yes"
fi

if [ "$LUAJIT" == "yes" ]; then
  git clone https://github.com/luajit/luajit $LUAJIT_BASE
  pushd $LUAJIT_BASE

  if [ "$LUA" == "luajit-2.0" ]; then
    git checkout v2.0.4
  elif [ "$LUA" == "luajit-2.1" ]; then
    git checkout v2.1
    perl -i -pe 's/INSTALL_TNAME=.+/INSTALL_TNAME= luajit/' Makefile
  fi

  make
  make install PREFIX=$LUA_DIR
  popd

  ln -sf $LUA_DIR/bin/luajit $LUA_DIR/bin/lua
else
  if [ "$LUA" == "lua5.1" ]; then
    curl http://www.lua.org/ftp/lua-5.1.5.tar.gz | tar xz
    pushd lua-5.1.5
  elif [ "$LUA" == "lua5.2" ]; then
    curl http://www.lua.org/ftp/lua-5.2.4.tar.gz | tar xz
    pushd lua-5.2.4
  elif [ "$LUA" == "lua5.3" ]; then
    curl http://www.lua.org/ftp/lua-5.3.2.tar.gz | tar xz
    pushd lua-5.3.2
  fi

  make $PLATFORM
  make install INSTALL_TOP=$LUA_DIR
  popd
fi

##########
# Luarocks
##########

LUAROCKS_BASE=luarocks-$LUAROCKS

git clone https://github.com/keplerproject/luarocks.git $LUAROCKS_BASE
pushd $LUAROCKS_BASE

git checkout v$LUAROCKS

if [ "$LUAJIT" == "yes" ]; then
  CONFIGURE_FLAGS="--with-lua-include=$LUA_DIR/include/$LUA"
elif [ "$LUA" == "lua5.1" ]; then
  CONFIGURE_FLAGS="--lua-version=5.1 --with-lua-include=$LUA_DIR/include"
elif [ "$LUA" == "lua5.2" ]; then
  CONFIGURE_FLAGS="--lua-version=5.2 --with-lua-include=$LUA_DIR/include"
elif [ "$LUA" == "lua5.3" ]; then
  CONFIGURE_FLAGS="--lua-version=5.3 --with-lua-include=$LUA_DIR/include"
fi

./configure \
  --prefix=$LUAROCKS_DIR \
  --with-lua-bin=$LUA_DIR/bin \
  $CONFIGURE_FLAGS

make build
make install
popd

rm -rf $LUAROCKS_BASE

if [ "$LUAJIT" == "yes" ]; then
  rm -rf $LUAJIT_BASE;
elif [ "$LUA" == "lua5.1" ]; then
  rm -rf lua-5.1.5;
elif [ "$LUA" == "lua5.2" ]; then
  rm -rf lua-5.2.4;
elif [ "$LUA" == "lua5.3" ]; then
  rm -rf lua-5.3.2;
fi
