#!/bin/bash

# A script for setting up environment for travis-ci testing.
# Sets up Lua and Luarocks.
# LUA must be "lua5.1", "lua5.2" or "luajit".
# luajit2.0 - master v2.0
# luajit2.1 - master v2.1

LUAJIT_BASE="LuaJIT-$LUAJIT_VERSION"

source .travis/platform.sh

LUAJIT_ENABLED="no"

if [ "$PLATFORM" == "macosx" ]; then
  case "$LUA" in
    "luajit" | "luajit2.0" | "luajit2.1")
      LUAJIT_ENABLED="yes"
      ;;
  esac
elif [ "$(expr substr $LUA 1 6)" == "luajit" ]; then
  LUAJIT_ENABLED="yes";
fi

if [ "$LUAJIT_ENABLED" == "yes" ]; then

  if [ "$LUA" == "luajit" ]; then
    curl http://luajit.org/download/$LUAJIT_BASE.tar.gz | tar xz;
  else
    git clone http://luajit.org/git/luajit-2.0.git $LUAJIT_BASE;
  fi

  cd $LUAJIT_BASE

  if [ "$LUA" == "luajit2.1" ]; then
    git checkout v2.1;
  fi

  make && sudo make install

  if [ "$LUA" == "luajit2.1" ]; then
    sudo ln -s /usr/local/bin/luajit-2.1.0-alpha /usr/local/bin/luajit
    sudo ln -s /usr/local/bin/luajit /usr/local/bin/lua;
  else
    sudo ln -s /usr/local/bin/luajit /usr/local/bin/lua;
  fi;

else
  case "$LUA" in
    "lua5.1")
      curl http://www.lua.org/ftp/lua-5.1.5.tar.gz | tar xz
      cd lua-5.1.5
      ;;
    "lua5.2")
      curl http://www.lua.org/ftp/lua-5.2.3.tar.gz | tar xz
      cd lua-5.2.3
      ;;
    "lua5.3")
      curl http://www.lua.org/ftp/lua-5.3.0.tar.gz | tar xz
      cd lua-5.3.0
      ;;
  esac
  sudo make $PLATFORM install;
fi

cd $TRAVIS_BUILD_DIR;

LUAROCKS_BASE=luarocks-$LUAROCKS_VERSION

# curl http://luarocks.org/releases/$LUAROCKS_BASE.tar.gz | tar xz

git clone https://github.com/keplerproject/luarocks.git $LUAROCKS_BASE
cd $LUAROCKS_BASE

git checkout v$LUAROCKS_VERSION

case "$LUA" in
  "luajit")
    ./configure --lua-suffix=jit --with-lua-include=/usr/local/include/luajit-2.0
    ;;
  "luajit2.0")
    ./configure --lua-suffix=jit --with-lua-include=/usr/local/include/luajit-2.0
    ;;
  "luajit2.1")
    ./configure --lua-suffix=jit --with-lua-include=/usr/local/include/luajit-2.1
    ;;
  *)
    ./configure
    ;;
esac

make build && sudo make install

cd $TRAVIS_BUILD_DIR

rm -rf $LUAROCKS_BASE

if [ "$LUAJIT_ENABLED" == "yes" ]; then
  rm -rf $LUAJIT_BASE;
else
  case "$LUA" in
    "lua5.1")
      rm -rf lua-5.1.5
      ;;
    "lua5.2")
      rm -rf lua-5.2.3
      ;;
    "lua5.3")
      rm -rf lua-5.3.0
      ;;
  esac
fi

