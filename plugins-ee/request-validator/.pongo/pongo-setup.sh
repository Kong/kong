# this runs inside the Kong container when it starts

# install pre-fetched private dependencies
cd /kong-plugin/lua-resty-openapi3-deserializer
luarocks remove lua-resty-openapi3-deserializer --force
luarocks make

# install public dependencies
find /kong-plugin -maxdepth 1 -type f -name '*.rockspec' -exec luarocks install --only-deps {} \;
