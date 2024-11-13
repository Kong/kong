#!/bin/bash -e

# template variables starts
luarocks_version="{{luarocks_version}}"
install_destdir="{{install_destdir}}"
build_destdir="{{build_destdir}}"

luarocks_exec="{{@@luarocks//:luarocks_exec}}"
luajit_path="{{@@openresty//:luajit}}"
luarocks_host_path="{{@@luarocks//:luarocks_host}}"
luarocks_wrap_script="{{@@//build/luarocks:luarocks_wrap_script.lua}}"
# template variables ends

mkdir -p $(dirname $@)


# install luarocks
$luarocks_exec install "luarocks $luarocks_version"

# use host configuration to invoke luarocks API to wrap a correct bin/luarocks script
rocks_tree=$(dirname $luarocks_exec)/luarocks_tree
host_luajit=$luajit_path/bin/luajit

host_luarocks_tree=$luarocks_host_path
export LUA_PATH="$build_destdir/share/lua/5.1/?.lua;$build_destdir/share/lua/5.1/?/init.lua;$host_luarocks_tree/share/lua/5.1/?.lua;$host_luarocks_tree/share/lua/5.1/?/init.lua;;"

ROCKS_CONFIG="luarocks_make_config.lua"
cat << EOF > $ROCKS_CONFIG
rocks_trees = {
    { name = [[system]], root = [[$rocks_tree]] }
}
EOF
export LUAROCKS_CONFIG=$ROCKS_CONFIG

$host_luajit $luarocks_wrap_script \
            luarocks $rocks_tree $install_destdir 2>&1 > $@.tmp

# write the luarocks config with host configuration
mkdir -p $rocks_tree/etc/luarocks
cat << EOF > $rocks_tree/etc/luarocks/config-5.1.lua
-- LuaRocks configuration
rocks_trees = {
        { name = "user", root = home .. "/.luarocks" };
        { name = "system", root = "$install_destdir" };
    }
    lua_interpreter = "luajit";
    variables = {
    LUA_DIR = "$install_destdir/openresty/luajit";
    LUA_INCDIR = "$install_destdir/openresty/luajit/include/luajit-2.1";
    LUA_BINDIR = "$install_destdir/openresty/luajit/bin";
}
EOF

sed -i -e "s|$build_destdir|$install_destdir|g" $rocks_tree/bin/luarocks
sed -i -e "s|$rocks_tree|$install_destdir|g" $rocks_tree/bin/luarocks

# only generate the output when the command succeeds
mv $@.tmp $@