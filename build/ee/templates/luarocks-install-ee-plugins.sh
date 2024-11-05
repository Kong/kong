#!/bin/bash -e

# [[ BEGIN template variables starts
luarocks_exec="{{@@luarocks//:luarocks_exec}}"
# the kong_template_genrule always render the shortest path of the given list of labels
# So we need to get the parent directory to install the rockspec files
resty_openapi3_deserializer="$(dirname {{@@resty_openapi3_deserializer//:all_srcs}})"
kong_gql="$(dirname {{@@kong_gql//:all_srcs}})"
# END template variables ]]

touch $@.tmp

cwd=$(pwd)
for dir in $resty_openapi3_deserializer $kong_gql; do
    echo "Installing library: $dir" >> $cwd/$@.tmp
    pushd $dir >> $cwd/$@.tmp
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