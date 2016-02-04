#!/bin/bash

set -e

########
# LuaJIT
########

mkdir -p $LUA_DIR
if [ ! "$(ls -A $LUA_DIR)" ]; then
  LUAJIT_BASE="LuaJIT"
  git clone https://github.com/luajit/luajit $LUAJIT_BASE

  pushd $LUAJIT_BASE
  if [ "$LUAJIT" == "2.1" ]; then
    git checkout v2.1
    perl -i -pe 's/INSTALL_TNAME=.+/INSTALL_TNAME= luajit/' Makefile
  else
    git checkout v2.0.4
  fi
  make
  make install PREFIX=$LUA_DIR
  popd

  ln -sf $LUA_DIR/bin/luajit $LUA_DIR/bin/lua

  rm -rf $LUAJIT_BASE
else
  echo "Lua found from cache at $LUA_DIR"
fi

##########
# Luarocks
##########

mkdir -p $LUAROCKS_DIR
if [ ! "$(ls -A $LUAROCKS_DIR)" ]; then
  LUAROCKS_BASE=luarocks-$LUAROCKS
  git clone https://github.com/keplerproject/luarocks.git $LUAROCKS_BASE

  pushd $LUAROCKS_BASE
  git checkout v$LUAROCKS
  ./configure \
    --prefix=$LUAROCKS_DIR \
    --with-lua-bin=$LUA_DIR/bin \
    --with-lua-include=$LUA_DIR/include/luajit-$LUAJIT
  make build
  make install
  popd

  rm -rf $LUAROCKS_BASE
else
  echo "Luarocks found from cache at $LUAROCKS_DIR"
fi
