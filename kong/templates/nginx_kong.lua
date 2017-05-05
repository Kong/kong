return [[
charset UTF-8;

error_log logs/error.log ${{LOG_LEVEL}};

> if anonymous_reports then
${{SYSLOG_REPORTS}}
> end

> if nginx_optimizations then
>-- send_timeout 60s;          # default value
>-- keepalive_timeout 75s;     # default value
>-- client_body_timeout 60s;   # default value
>-- client_header_timeout 60s; # default value
>-- tcp_nopush on;             # disabled until benchmarked
>-- proxy_buffer_size 128k;    # disabled until benchmarked
>-- proxy_buffers 4 256k;      # disabled until benchmarked
>-- proxy_busy_buffers_size 256k; # disabled until benchmarked
>-- reset_timedout_connection on; # disabled until benchmarked
> end

client_max_body_size 0;
proxy_ssl_server_name on;
underscores_in_headers on;

real_ip_header X-Forwarded-For;
set_real_ip_from 0.0.0.0/0;
real_ip_recursive on;

lua_package_path '${{LUA_PACKAGE_PATH}};;';
lua_package_cpath '${{LUA_PACKAGE_CPATH}};;';
lua_code_cache ${{LUA_CODE_CACHE}};
lua_socket_pool_size ${{LUA_SOCKET_POOL_SIZE}};
lua_max_running_timers 4096;
lua_max_pending_timers 16384;
lua_shared_dict kong 4m;
lua_shared_dict cache ${{MEM_CACHE_SIZE}};
lua_shared_dict cache_locks 100k;
lua_shared_dict process_events 1m;
lua_shared_dict cassandra 5m;
lua_socket_log_errors off;
> if lua_ssl_trusted_certificate then
lua_ssl_trusted_certificate '${{LUA_SSL_TRUSTED_CERTIFICATE}}';
lua_ssl_verify_depth ${{LUA_SSL_VERIFY_DEPTH}};
> end

init_by_lua_block {
    require 'luarocks.loader'
    require 'resty.core'
    kong = require 'kong'
    kong.init()
}

init_worker_by_lua_block {
    kong.init_worker()
}

proxy_next_upstream_tries 999;

upstream kong_upstream {
    server 0.0.0.1;
    balancer_by_lua_block {
        kong.balancer()
    }
    keepalive ${{UPSTREAM_KEEPALIVE}};
}

map $http_upgrade $upstream_connection {
    default keep-alive;
    websocket upgrade;
}

map $http_upgrade $upstream_upgrade {
    default '';
    websocket websocket;
}

server {
    server_name kong;
    listen ${{PROXY_LISTEN}};
    error_page 404 408 411 412 413 414 417 /kong_error_handler;
    error_page 500 502 503 504 /kong_error_handler;

    access_log logs/access.log;

> if ssl then
    listen ${{PROXY_LISTEN_SSL}} ssl;
    ssl_certificate ${{SSL_CERT}};
    ssl_certificate_key ${{SSL_CERT_KEY}};
    ssl_protocols TLSv1.1 TLSv1.2;
    ssl_certificate_by_lua_block {
        kong.ssl_certificate()
    }
> end

    location / {
        set $upstream_host nil;
        set $upstream_scheme nil;

        rewrite_by_lua_block {
            kong.rewrite()
        }

        access_by_lua_block {
            kong.access()
        }

        proxy_http_version 1.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Host $upstream_host;
        proxy_set_header Upgrade $upstream_upgrade;
        proxy_set_header Connection $upstream_connection;
        proxy_pass_header Server;

        proxy_ssl_name $upstream_host;

        proxy_pass $upstream_scheme://kong_upstream;

        header_filter_by_lua_block {
            kong.header_filter()
        }

        body_filter_by_lua_block {
            kong.body_filter()
        }

        log_by_lua_block {
            kong.log()
        }
    }

    location = /kong_error_handler {
        internal;
        content_by_lua_block {
            require('kong.core.error_handlers')(ngx)
        }
    }
}

server {
    server_name kong_admin;
    listen ${{ADMIN_LISTEN}};

    access_log logs/admin_access.log;

    client_max_body_size 10m;
    client_body_buffer_size 10m;

> if admin_ssl then
    listen ${{ADMIN_LISTEN_SSL}} ssl;
    ssl_certificate ${{ADMIN_SSL_CERT}};
    ssl_certificate_key ${{ADMIN_SSL_CERT_KEY}};
    ssl_protocols TLSv1.1 TLSv1.2;
> end

    location / {
        default_type application/json;
        content_by_lua_block {
            ngx.header['Access-Control-Allow-Origin'] = '*'

            if ngx.req.get_method() == 'OPTIONS' then
                ngx.header['Access-Control-Allow-Methods'] = 'GET,HEAD,PUT,PATCH,POST,DELETE'
                ngx.header['Access-Control-Allow-Headers'] = 'Content-Type'
                ngx.exit(204)
            end

            require('lapis').serve('kong.api')
        }
    }

    location /nginx_status {
        internal;
        access_log off;
        stub_status;
    }

    location /robots.txt {
        return 200 'User-agent: *\nDisallow: /';
    }
}
]]
