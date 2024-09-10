#!/bin/bash -e

# template variables starts
luarocks_make="{{@@luarocks//:luarocks_make}}"
luajit="{{@@openresty//:luajit}}"
source_dir="{{source_dir}}"
# template variables ends

touch $@.tmp
cwd=$(pwd)

LUAROCKS=$cwd/$(dirname $luarocks_make)/luarocks_tree 2>> $cwd/$@.tmp
src=$LUAROCKS/share/lua/5.1/kong/${source_dir}

LUAJIT=$cwd/$luajit/bin/luajit
export LUA_PATH="$cwd/$luajit/share/luajit-2.1/?.lua;;"
$LUAJIT 2>> $cwd/$@.tmp

pushd $src 2>&1 >> $cwd/$@.tmp

    find . -type f -name '*.lua' -print | while read -r source_path; do
        $LUAJIT \
            -b \
            -g \
            -t raw \
            -- \
            "$source_path" \
            "${source_path//.lua/.ljbc}"

        rm -fv "$source_path" 2>&1 >> $cwd/$@.tmp
    done

popd 2>&1 >> $cwd/$@.tmp

# only generate the output when the command succeeds
mv $@.tmp $@