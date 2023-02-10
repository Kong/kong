return [[
pid pids/nginx.pid;
error_log ${{PROXY_ERROR_LOG}} ${{LOG_LEVEL}};

# injected nginx_main_* directives
> for _, el in ipairs(nginx_main_directives) do
$(el.name) $(el.value);
> end

> if database == "off" then
lmdb_environment_path ${{LMDB_ENVIRONMENT_PATH}};
lmdb_map_size         ${{LMDB_MAP_SIZE}};
> end

events {
    # injected nginx_events_* directives
> for _, el in ipairs(nginx_events_directives) do
    $(el.name) $(el.value);
> end
}

> if wasm then
wasm {
> for _, module in ipairs(wasm_modules_parsed) do
    module $(module.name) $(module.path);
> end
}

env RUST_BACKTRACE=1;
env WASMTIME_BACKTRACE_DETAILS=1;
> end

> if role == "control_plane" or #proxy_listeners > 0 or #admin_listeners > 0 or #status_listeners > 0 then
http {
    resolver 1.1.1.1;
    include 'nginx-kong.conf';
}
> end

> if #stream_listeners > 0 or cluster_ssl_tunnel then
stream {
> if #stream_listeners > 0 then
    include 'nginx-kong-stream.conf';
> end

> if cluster_ssl_tunnel then
    server {
        listen unix:${{PREFIX}}/cluster_proxy_ssl_terminator.sock;

        proxy_pass ${{cluster_ssl_tunnel}};
        proxy_ssl on;
        # as we are essentially talking in HTTPS, passing SNI should default turned on
        proxy_ssl_server_name on;
> if proxy_server_ssl_verify then
        proxy_ssl_verify on;
> if lua_ssl_trusted_certificate_combined then
        proxy_ssl_trusted_certificate '${{LUA_SSL_TRUSTED_CERTIFICATE_COMBINED}}';
> end
        proxy_ssl_verify_depth 5; # 5 should be sufficient
> else
        proxy_ssl_verify off;
> end
        proxy_socket_keepalive on;
    }
> end -- cluster_ssl_tunnel

}
> end
]]
