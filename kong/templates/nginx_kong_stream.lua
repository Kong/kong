return [[

log_format basic '$remote_addr [$time_local] '
                 '$protocol $status $bytes_sent $bytes_received '
                 '$session_time';

lua_package_path       '${{LUA_PACKAGE_PATH}};;';
lua_package_cpath      '${{LUA_PACKAGE_CPATH}};;';
lua_socket_pool_size   ${{LUA_SOCKET_POOL_SIZE}};
lua_socket_log_errors  off;
lua_max_running_timers 4096;
lua_max_pending_timers 16384;
lua_ssl_verify_depth   ${{LUA_SSL_VERIFY_DEPTH}};
> if lua_ssl_trusted_certificate_combined then
lua_ssl_trusted_certificate '${{LUA_SSL_TRUSTED_CERTIFICATE_COMBINED}}';
> end

lua_shared_dict stream_kong                        5m;
lua_shared_dict stream_kong_locks                  8m;
lua_shared_dict stream_kong_healthchecks           5m;
lua_shared_dict stream_kong_process_events         5m;
lua_shared_dict stream_kong_cluster_events         5m;
lua_shared_dict stream_kong_rate_limiting_counters 12m;
lua_shared_dict stream_kong_core_db_cache          ${{MEM_CACHE_SIZE}};
lua_shared_dict stream_kong_core_db_cache_miss     12m;
lua_shared_dict stream_kong_db_cache               ${{MEM_CACHE_SIZE}};
lua_shared_dict stream_kong_db_cache_miss          12m;
> if database == "off" then
lua_shared_dict stream_kong_core_db_cache_2        ${{MEM_CACHE_SIZE}};
lua_shared_dict stream_kong_core_db_cache_miss_2   12m;
lua_shared_dict stream_kong_db_cache_2             ${{MEM_CACHE_SIZE}};
lua_shared_dict stream_kong_db_cache_miss_2        12m;
> end
> if database == "cassandra" then
lua_shared_dict stream_kong_cassandra              5m;
> end

> if ssl_ciphers then
ssl_ciphers ${{SSL_CIPHERS}};
> end

# injected nginx_stream_* directives
> for _, el in ipairs(nginx_stream_directives) do
$(el.name) $(el.value);
> end

init_by_lua_block {
    -- shared dictionaries conflict between stream/http modules. use a prefix.
    local shared = ngx.shared
    local stream_shdict_prefix = "stream_"
    ngx.shared = setmetatable({}, {
        __pairs = function()
            local i
            return function()
                local k, v = next(shared, i)
                i = k
                if k and k:sub(1, #stream_shdict_prefix) == stream_shdict_prefix then
                    k = k:sub(#stream_shdict_prefix + 1)
                end
                return k, v
            end
        end,
        __index = function(t, k)
            return shared[stream_shdict_prefix .. k]
        end,
    })

    Kong = require 'kong'
    Kong.init()
}

init_worker_by_lua_block {
    Kong.init_worker()
}

upstream kong_upstream {
    server 0.0.0.1:1;
    balancer_by_lua_block {
        Kong.balancer()
    }

    # injected nginx_supstream_* directives
> for _, el in ipairs(nginx_supstream_directives) do
    $(el.name) $(el.value);
> end
}

> if #stream_listeners > 0 then
server {
> for _, entry in ipairs(stream_listeners) do
    listen $(entry.listener);
> end

    access_log ${{PROXY_STREAM_ACCESS_LOG}};
    error_log ${{PROXY_STREAM_ERROR_LOG}} ${{LOG_LEVEL}};

> for _, ip in ipairs(trusted_ips) do
    set_real_ip_from $(ip);
> end

    # injected nginx_sproxy_* directives
> for _, el in ipairs(nginx_sproxy_directives) do
    $(el.name) $(el.value);
> end

> if stream_proxy_ssl_enabled then
> for i = 1, #ssl_cert do
    ssl_certificate     $(ssl_cert[i]);
    ssl_certificate_key $(ssl_cert_key[i]);
> end
    ssl_session_cache   shared:StreamSSL:10m;
    ssl_certificate_by_lua_block {
        Kong.ssl_certificate()
    }
> end

    preread_by_lua_block {
        Kong.preread()
    }

    proxy_ssl on;
    proxy_ssl_server_name on;
> if client_ssl then
    proxy_ssl_certificate ${{CLIENT_SSL_CERT}};
    proxy_ssl_certificate_key ${{CLIENT_SSL_CERT_KEY}};
> end
    proxy_pass kong_upstream;

    log_by_lua_block {
        Kong.log()
    }
}

> if database == "off" then
server {
    listen unix:${{PREFIX}}/stream_config.sock;

    error_log  ${{ADMIN_ERROR_LOG}} ${{LOG_LEVEL}};

    content_by_lua_block {
        Kong.stream_config_listener()
    }
}
> end -- database == "off"

server {        # ignore (and close }, to ignore content)
    listen unix:${{PREFIX}}/stream_rpc.sock udp;
    error_log  ${{ADMIN_ERROR_LOG}} ${{LOG_LEVEL}};
    content_by_lua_block {
        Kong.stream_api()
    }
}

> end -- #stream_listeners > 0
]]
