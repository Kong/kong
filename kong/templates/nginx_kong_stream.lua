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

include 'nginx-kong-stream-inject.conf';

lua_shared_dict stream_kong                        5m;
lua_shared_dict stream_kong_locks                  8m;
lua_shared_dict stream_kong_healthchecks           5m;
lua_shared_dict stream_kong_cluster_events         5m;
lua_shared_dict stream_kong_rate_limiting_counters 12m;
lua_shared_dict stream_kong_core_db_cache          ${{MEM_CACHE_SIZE}};
lua_shared_dict stream_kong_core_db_cache_miss     12m;
lua_shared_dict stream_kong_db_cache               ${{MEM_CACHE_SIZE}};
lua_shared_dict stream_kong_db_cache_miss          12m;
lua_shared_dict stream_kong_secrets                5m;

> if ssl_ciphers then
ssl_ciphers ${{SSL_CIPHERS}};
> end

# injected nginx_stream_* directives
> for _, el in ipairs(nginx_stream_directives) do
$(el.name) $(el.value);
> end

> if ssl_cipher_suite == 'old' then
lua_ssl_conf_command CipherString DEFAULT:@SECLEVEL=0;
proxy_ssl_conf_command CipherString DEFAULT:@SECLEVEL=0;
ssl_conf_command CipherString DEFAULT:@SECLEVEL=0;
> end

init_by_lua_block {
> if test and coverage then
    require 'luacov'
    jit.off()
> end -- test and coverage
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
# non-SSL listeners, and the SSL terminator
server {
> for _, entry in ipairs(stream_listeners) do
> if not entry.ssl then
    listen $(entry.listener);
> end
> end

> if stream_proxy_ssl_enabled then
    listen unix:${{SOCKET_PATH}}/${{STREAM_TLS_TERMINATE_SOCK}} ssl proxy_protocol;
> end

    access_log ${{PROXY_STREAM_ACCESS_LOG}};
    error_log ${{PROXY_STREAM_ERROR_LOG}} ${{LOG_LEVEL}};

> for _, ip in ipairs(trusted_ips) do
    set_real_ip_from $(ip);
> end
    set_real_ip_from unix:;

    # injected nginx_sproxy_* directives
> for _, el in ipairs(nginx_sproxy_directives) do
    $(el.name) $(el.value);
> end

> if stream_proxy_ssl_enabled then
> for i = 1, #ssl_cert do
    ssl_certificate     $(ssl_cert[i]);
    ssl_certificate_key $(ssl_cert_key[i]);
> end
    ssl_session_cache   shared:StreamSSL:${{SSL_SESSION_CACHE_SIZE}};
    ssl_certificate_by_lua_block {
        Kong.ssl_certificate()
    }
    ssl_client_hello_by_lua_block {
        Kong.ssl_client_hello()
    }
> end

    set $upstream_host '';
    preread_by_lua_block {
        Kong.preread()
    }
    proxy_ssl_name $upstream_host;

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

> if stream_proxy_ssl_enabled then
# SSL listeners, but only preread the handshake here
server {
> for _, entry in ipairs(stream_listeners) do
> if entry.ssl then
    listen $(entry.listener:gsub(" ssl", ""));
> end
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

    preread_by_lua_block {
        Kong.preread()
    }

    ssl_preread on;

    proxy_protocol on;

    set $kong_tls_preread_block 1;
    set $kong_tls_preread_block_upstream '';
    proxy_pass $kong_tls_preread_block_upstream;
}

server {
    listen unix:${{SOCKET_PATH}}/${{STREAM_TLS_PASSTHROUGH_SOCK}} proxy_protocol;

    access_log ${{PROXY_STREAM_ACCESS_LOG}};
    error_log ${{PROXY_STREAM_ERROR_LOG}} ${{LOG_LEVEL}};

    set_real_ip_from unix:;

    # injected nginx_sproxy_* directives
> for _, el in ipairs(nginx_sproxy_directives) do
    $(el.name) $(el.value);
> end

    preread_by_lua_block {
        Kong.preread()
    }

    ssl_preread on;

    set $kong_tls_passthrough_block 1;

    proxy_pass kong_upstream;

    log_by_lua_block {
        Kong.log()
    }
}
> end -- stream_proxy_ssl_enabled

> if database == "off" then
server {
    listen unix:${{SOCKET_PATH}}/${{STREAM_CONFIG_SOCK}};

    error_log  ${{ADMIN_ERROR_LOG}} ${{LOG_LEVEL}};

    content_by_lua_block {
        Kong.stream_config_listener()
    }
}
> end -- database == "off"

server {        # ignore (and close }, to ignore content)
    listen unix:${{SOCKET_PATH}}/${{STREAM_RPC_SOCK}};
    error_log  ${{ADMIN_ERROR_LOG}} ${{LOG_LEVEL}};
    content_by_lua_block {
        Kong.stream_api()
    }
}
> end -- #stream_listeners > 0

server {
    listen unix:${{SOCKET_PATH}}/${{STREAM_WORKER_EVENTS_SOCK}};
    error_log  ${{ADMIN_ERROR_LOG}} ${{LOG_LEVEL}};
    access_log off;
    content_by_lua_block {
      require("resty.events.compat").run()
    }
}
]]
