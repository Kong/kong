#!/bin/bash -e

# template variables starts
luarocks_exec="{{@@luarocks//:luarocks_exec}}"
# template variables ends

touch $@.tmp

cwd=$(pwd)
for dir in lua-resty-openapi3-deserializer kong-gql; do
    echo "Installing library: $dir" >> $cwd/$@.tmp
    pushd distribution/$dir >> $cwd/$@.tmp
        $cwd/$luarocks_exec make *.rockspec >> $cwd/$@.tmp
    popd >> $cwd/$@.tmp
done

for plugin_ee in plugins-ee/*; do
    if [ -d "$plugin_ee" ]; then
        echo "Installing plugin: $(basename $plugin_ee)" >> $cwd/$@.tmp
        pushd $plugin_ee >> $cwd/$@.tmp
            $cwd/$luarocks_exec make *.rockspec >> $cwd/$@.tmp
        popd >> $cwd/$@.tmp
    fi
done

# HACK
cp -r plugins-ee/saml/xml $(dirname $luarocks_exec)/luarocks_tree/share/

# only generate the output when the command succeeds
mv $@.tmp $@