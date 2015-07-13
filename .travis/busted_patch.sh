#!/bin/bash

sudo sed -i.bak s@/usr/local/bin/luajit@/usr/bin/lua@g /usr/local/bin/busted # Forcing busted to use Lua
sudo sed -i.bak s@/usr/local/bin/luajit@/usr/bin/lua@g /usr/local/bin/luarocks # Forcing Luarocks to use Lua

sudo luarocks install ljsyscall # Installing "ffi"
sudo luarocks install luabitop # Installing "bit"