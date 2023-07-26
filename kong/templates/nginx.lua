-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return [[
pid pids/nginx.pid;
error_log ${{PROXY_ERROR_LOG}} ${{LOG_LEVEL}};

# injected nginx_main_* directives
> for _, el in ipairs(nginx_main_directives) do
$(el.name) $(el.value);
> end

env KONG_LICENSE_DATA;
env KONG_LICENSE_PATH;

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

> if role == "control_plane" or #proxy_listeners > 0 or #admin_listeners > 0 or #status_listeners > 0 then
http {
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
