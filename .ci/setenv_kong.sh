export LUAROCKS_DIR=$HOME/luarocks

export PATH=$LUA_DIR/bin:$LUAROCKS_DIR/bin:$OPENRESTY_DIR/nginx/sbin:$SERF_DIR:$DNSMASQ_DIR/usr/local/sbin:$PATH

bash .ci/setup_lua.sh
bash .ci/setup_openresty.sh
bash .ci/setup_serf.sh
bash .ci/setup_dnsmasq.sh

eval `luarocks path`
