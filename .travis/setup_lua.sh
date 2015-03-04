#! /bin/bash

# A script for setting up environment for travis-ci testing.
# Sets up Lua and Luarocks.
# LUA must be "lua5.1", "lua5.2" or "luajit".
# luajit2.0 - master v2.0
# luajit2.1 - master v2.1

LUAJIT_BASE="LuaJIT-2.0.3"

source .travis/platform.sh

LUAJIT="no"

if [ "$PLATFORM" == "macosx" ]; then
  if [ "$LUA" == "luajit" ]; then
    LUAJIT="yes";
  fi
  if [ "$LUA" == "luajit2.0" ]; then
    LUAJIT="yes";
  fi
  if [ "$LUA" == "luajit2.1" ]; then
    LUAJIT="yes";
  fi;
elif [ "$(expr substr $LUA 1 6)" == "luajit" ]; then
  LUAJIT="yes";
fi

if [ "$LUAJIT" == "yes" ]; then

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
  if [ "$LUA" == "lua5.1" ]; then
    curl http://www.lua.org/ftp/lua-5.1.5.tar.gz | tar xz
    cd lua-5.1.5;
  elif [ "$LUA" == "lua5.2" ]; then
    curl http://www.lua.org/ftp/lua-5.2.3.tar.gz | tar xz
    cd lua-5.2.3;
  elif [ "$LUA" == "lua5.3" ]; then
    curl http://www.lua.org/ftp/lua-5.3.0.tar.gz | tar xz
    cd lua-5.3.0;
  fi
  sudo make $PLATFORM install;
fi

cd $TRAVIS_BUILD_DIR;

LUAROCKS_BASE=luarocks-$LUAROCKS

# curl http://luarocks.org/releases/$LUAROCKS_BASE.tar.gz | tar xz

git clone https://github.com/keplerproject/luarocks.git $LUAROCKS_BASE
cd $LUAROCKS_BASE

git checkout v$LUAROCKS

if [ "$LUA" == "luajit" ]; then
  ./configure --lua-suffix=jit --with-lua-include=/usr/local/include/luajit-2.0;
elif [ "$LUA" == "luajit2.0" ]; then
  ./configure --lua-suffix=jit --with-lua-include=/usr/local/include/luajit-2.0;
elif [ "$LUA" == "luajit2.1" ]; then
  ./configure --lua-suffix=jit --with-lua-include=/usr/local/include/luajit-2.1;
else
  ./configure;
fi

make build && sudo make install

cd $TRAVIS_BUILD_DIR

rm -rf $LUAROCKS_BASE

if [ "$LUAJIT" == "yes" ]; then
  rm -rf $LUAJIT_BASE;
elif [ "$LUA" == "lua5.1" ]; then
  rm -rf lua-5.1.5;
elif [ "$LUA" == "lua5.2" ]; then
  rm -rf lua-5.2.3;
elif [ "$LUA" == "lua5.3" ]; then
  rm -rf lua-5.3.0;
fi
