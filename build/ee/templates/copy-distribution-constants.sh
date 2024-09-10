#!/bin/bash -e

# template variables starts
luarocks_make="{{@@luarocks//:luarocks_make}}"
distributions_constants="{{@@//build/ee:distributions_constants}}"
# template variables ends

touch $@.tmp
cwd=$(pwd)

LUAROCKS=$(dirname $luarocks_make)/luarocks_tree 2>> $cwd/$@.tmp
dest=${LUAROCKS}/share/lua/5.1/kong/enterprise_edition/distributions_constants.lua

cp -v $distributions_constants ${dest} 2>&1 >> $cwd/$@.tmp

# only generate the output when the command succeeds
mv $@.tmp $@