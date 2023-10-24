-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return [[
server_tokens off;

error_log ${{PROXY_ERROR_LOG}} ${{LOG_LEVEL}};

lua_package_path       '${{LUA_PACKAGE_PATH}};;';
lua_package_cpath      '${{LUA_PACKAGE_CPATH}};;';
lua_socket_pool_size   ${{LUA_SOCKET_POOL_SIZE}};
lua_socket_log_errors  off;
lua_max_running_timers 4096;
lua_max_pending_timers 16384;

include 'nginx-kong-inject.conf';

lua_shared_dict kong                        5m;
lua_shared_dict kong_locks                  8m;
lua_shared_dict kong_healthchecks           5m;
lua_shared_dict kong_cluster_events         5m;
lua_shared_dict kong_rate_limiting_counters 12m;
lua_shared_dict kong_core_db_cache          ${{MEM_CACHE_SIZE}};
lua_shared_dict kong_core_db_cache_miss     12m;
lua_shared_dict kong_db_cache               ${{MEM_CACHE_SIZE}};
lua_shared_dict kong_db_cache_miss          12m;
lua_shared_dict kong_secrets                5m;

lua_shared_dict kong_vitals_counters 50m;
lua_shared_dict kong_vitals_lists   1m;
lua_shared_dict kong_vitals 1m;
lua_shared_dict kong_counters   1m;
lua_shared_dict kong_reports_consumers       10m;
lua_shared_dict kong_reports_routes          1m;
lua_shared_dict kong_reports_services        1m;
lua_shared_dict kong_reports_workspaces 1m;
lua_shared_dict kong_keyring 5m;
lua_shared_dict kong_profiling_state 1536k;  # 1.5 MBytes

underscores_in_headers on;
> if ssl_ciphers then
ssl_ciphers ${{SSL_CIPHERS}};
> end

# injected nginx_http_* directives
> for _, el in ipairs(nginx_http_directives) do
$(el.name) $(el.value);
> end

init_by_lua_block {
> if test and coverage then
    require 'luacov'
    jit.off()
> end -- test and coverage
    Kong = require 'kong'
    Kong.init()
}

init_worker_by_lua_block {
    Kong.init_worker()
}

exit_worker_by_lua_block {
    Kong.exit_worker()
}

> if (role == "traditional" or role == "data_plane") and #proxy_listeners > 0 then
log_format kong_log_format '$remote_addr - $remote_user [$time_local] '
                           '"$request" $status $body_bytes_sent '
                           '"$http_referer" "$http_user_agent" '
                           'kong_request_id: "$kong_request_id"';

# Load variable indexes
lua_kong_load_var_index default;
lua_kong_load_var_index $http_x_kong_request_debug;
lua_kong_load_var_index $http_x_kong_request_debug_token;
lua_kong_load_var_index $http_x_kong_request_debug_log;

upstream kong_upstream {
    server 0.0.0.1;

    # injected nginx_upstream_* directives
> for _, el in ipairs(nginx_upstream_directives) do
    $(el.name) $(el.value);
> end

    balancer_by_lua_block {
        Kong.balancer()
    }
}

server {
    server_name kong;
> for _, entry in ipairs(proxy_listeners) do
    listen $(entry.listener);
> end

    error_page 400 404 405 408 411 412 413 414 417 494 /kong_error_handler;
    error_page 500 502 503 504                     /kong_error_handler;

    # Append the kong request id to the error log
    # https://github.com/Kong/lua-kong-nginx-module#lua_kong_error_log_request_id
    lua_kong_error_log_request_id $kong_request_id;

> if proxy_access_log_enabled then
    access_log ${{PROXY_ACCESS_LOG}} kong_log_format;
> else
    access_log off;
> end

    error_log  ${{PROXY_ERROR_LOG}} ${{LOG_LEVEL}};

> if proxy_ssl_enabled then
> for i = 1, #ssl_cert do
    ssl_certificate     $(ssl_cert[i]);
    ssl_certificate_key $(ssl_cert_key[i]);
> end
    ssl_session_cache   shared:SSL:${{SSL_SESSION_CACHE_SIZE}};
    ssl_certificate_by_lua_block {
        Kong.ssl_certificate()
    }
> end

    # injected nginx_proxy_* directives
> for _, el in ipairs(nginx_proxy_directives) do
    $(el.name) $(el.value);
> end
> for _, ip in ipairs(trusted_ips) do
    set_real_ip_from $(ip);
> end

    rewrite_by_lua_block {
        Kong.rewrite()
    }

    access_by_lua_block {
        Kong.access()
    }

    header_filter_by_lua_block {
        Kong.header_filter()
    }

    body_filter_by_lua_block {
        Kong.body_filter()
    }

    log_by_lua_block {
        Kong.log()
    }

    location / {
        default_type                     '';

        set $ctx_ref                     '';
        set $upstream_te                 '';
        set $upstream_host               '';
        set $upstream_upgrade            '';
        set $upstream_connection         '';
        set $upstream_scheme             '';
        set $upstream_uri                '';
        set $upstream_x_forwarded_for    '';
        set $upstream_x_forwarded_proto  '';
        set $upstream_x_forwarded_host   '';
        set $upstream_x_forwarded_port   '';
        set $upstream_x_forwarded_path   '';
        set $upstream_x_forwarded_prefix '';
        set $kong_proxy_mode             'http';

        set $set_request_id $kong_request_id;

        proxy_http_version      1.1;
        proxy_buffering          on;
        proxy_request_buffering  on;

        proxy_set_header      TE                 $upstream_te;
        proxy_set_header      Host               $upstream_host;
        proxy_set_header      Upgrade            $upstream_upgrade;
        proxy_set_header      Connection         $upstream_connection;
        proxy_set_header      X-Forwarded-For    $upstream_x_forwarded_for;
        proxy_set_header      X-Forwarded-Proto  $upstream_x_forwarded_proto;
        proxy_set_header      X-Forwarded-Host   $upstream_x_forwarded_host;
        proxy_set_header      X-Forwarded-Port   $upstream_x_forwarded_port;
        proxy_set_header      X-Forwarded-Path   $upstream_x_forwarded_path;
        proxy_set_header      X-Forwarded-Prefix $upstream_x_forwarded_prefix;
        proxy_set_header      X-Real-IP          $remote_addr;
> if enabled_headers_upstream["X-Kong-Request-Id"] then
        proxy_set_header      X-Kong-Request-Id  $kong_request_id;
> end
        proxy_pass_header     Server;
        proxy_pass_header     Date;
        proxy_ssl_name        $upstream_host;
        proxy_ssl_server_name on;
> if client_ssl then
        proxy_ssl_certificate ${{CLIENT_SSL_CERT}};
        proxy_ssl_certificate_key ${{CLIENT_SSL_CERT_KEY}};
> end
        proxy_pass            $upstream_scheme://kong_upstream$upstream_uri;
    }

    location @unbuffered {
        internal;
        default_type         '';
        set $kong_proxy_mode 'unbuffered';

        proxy_http_version      1.1;
        proxy_buffering         off;
        proxy_request_buffering off;

        proxy_set_header      TE                 $upstream_te;
        proxy_set_header      Host               $upstream_host;
        proxy_set_header      Upgrade            $upstream_upgrade;
        proxy_set_header      Connection         $upstream_connection;
        proxy_set_header      X-Forwarded-For    $upstream_x_forwarded_for;
        proxy_set_header      X-Forwarded-Proto  $upstream_x_forwarded_proto;
        proxy_set_header      X-Forwarded-Host   $upstream_x_forwarded_host;
        proxy_set_header      X-Forwarded-Port   $upstream_x_forwarded_port;
        proxy_set_header      X-Forwarded-Path   $upstream_x_forwarded_path;
        proxy_set_header      X-Forwarded-Prefix $upstream_x_forwarded_prefix;
        proxy_set_header      X-Real-IP          $remote_addr;
> if enabled_headers_upstream["X-Kong-Request-Id"] then
        proxy_set_header      X-Kong-Request-Id  $kong_request_id;
> end
        proxy_pass_header     Server;
        proxy_pass_header     Date;
        proxy_ssl_name        $upstream_host;
        proxy_ssl_server_name on;
> if client_ssl then
        proxy_ssl_certificate ${{CLIENT_SSL_CERT}};
        proxy_ssl_certificate_key ${{CLIENT_SSL_CERT_KEY}};
> end
        proxy_pass            $upstream_scheme://kong_upstream$upstream_uri;
    }

    location @unbuffered_request {
        internal;
        default_type         '';
        set $kong_proxy_mode 'unbuffered';

        proxy_http_version      1.1;
        proxy_buffering          on;
        proxy_request_buffering off;

        proxy_set_header      TE                 $upstream_te;
        proxy_set_header      Host               $upstream_host;
        proxy_set_header      Upgrade            $upstream_upgrade;
        proxy_set_header      Connection         $upstream_connection;
        proxy_set_header      X-Forwarded-For    $upstream_x_forwarded_for;
        proxy_set_header      X-Forwarded-Proto  $upstream_x_forwarded_proto;
        proxy_set_header      X-Forwarded-Host   $upstream_x_forwarded_host;
        proxy_set_header      X-Forwarded-Port   $upstream_x_forwarded_port;
        proxy_set_header      X-Forwarded-Path   $upstream_x_forwarded_path;
        proxy_set_header      X-Forwarded-Prefix $upstream_x_forwarded_prefix;
        proxy_set_header      X-Real-IP          $remote_addr;
> if enabled_headers_upstream["X-Kong-Request-Id"] then
        proxy_set_header      X-Kong-Request-Id  $kong_request_id;
> end
        proxy_pass_header     Server;
        proxy_pass_header     Date;
        proxy_ssl_name        $upstream_host;
        proxy_ssl_server_name on;
> if client_ssl then
        proxy_ssl_certificate ${{CLIENT_SSL_CERT}};
        proxy_ssl_certificate_key ${{CLIENT_SSL_CERT_KEY}};
> end
        proxy_pass            $upstream_scheme://kong_upstream$upstream_uri;
    }

    location @unbuffered_response {
        internal;
        default_type         '';
        set $kong_proxy_mode 'unbuffered';

        proxy_http_version      1.1;
        proxy_buffering         off;
        proxy_request_buffering  on;

        proxy_set_header      TE                 $upstream_te;
        proxy_set_header      Host               $upstream_host;
        proxy_set_header      Upgrade            $upstream_upgrade;
        proxy_set_header      Connection         $upstream_connection;
        proxy_set_header      X-Forwarded-For    $upstream_x_forwarded_for;
        proxy_set_header      X-Forwarded-Proto  $upstream_x_forwarded_proto;
        proxy_set_header      X-Forwarded-Host   $upstream_x_forwarded_host;
        proxy_set_header      X-Forwarded-Port   $upstream_x_forwarded_port;
        proxy_set_header      X-Forwarded-Path   $upstream_x_forwarded_path;
        proxy_set_header      X-Forwarded-Prefix $upstream_x_forwarded_prefix;
        proxy_set_header      X-Real-IP          $remote_addr;
> if enabled_headers_upstream["X-Kong-Request-Id"] then
        proxy_set_header      X-Kong-Request-Id  $kong_request_id;
> end
        proxy_pass_header     Server;
        proxy_pass_header     Date;
        proxy_ssl_name        $upstream_host;
        proxy_ssl_server_name on;
> if client_ssl then
        proxy_ssl_certificate ${{CLIENT_SSL_CERT}};
        proxy_ssl_certificate_key ${{CLIENT_SSL_CERT_KEY}};
> end
        proxy_pass            $upstream_scheme://kong_upstream$upstream_uri;
    }

    location @grpc {
        internal;
        default_type         '';
        set $kong_proxy_mode 'grpc';

        grpc_set_header      TE                 $upstream_te;
        grpc_set_header      X-Forwarded-For    $upstream_x_forwarded_for;
        grpc_set_header      X-Forwarded-Proto  $upstream_x_forwarded_proto;
        grpc_set_header      X-Forwarded-Host   $upstream_x_forwarded_host;
        grpc_set_header      X-Forwarded-Port   $upstream_x_forwarded_port;
        grpc_set_header      X-Forwarded-Path   $upstream_x_forwarded_path;
        grpc_set_header      X-Forwarded-Prefix $upstream_x_forwarded_prefix;
        grpc_set_header      X-Real-IP          $remote_addr;
> if enabled_headers_upstream["X-Kong-Request-Id"] then
        grpc_set_header      X-Kong-Request-Id  $kong_request_id;
> end
        grpc_pass_header     Server;
        grpc_pass_header     Date;
        grpc_ssl_name        $upstream_host;
        grpc_ssl_server_name on;
> if client_ssl then
        grpc_ssl_certificate ${{CLIENT_SSL_CERT}};
        grpc_ssl_certificate_key ${{CLIENT_SSL_CERT_KEY}};
> end
        grpc_pass            $upstream_scheme://kong_upstream;
    }

    location @websocket {
        internal;
        default_type         '';
        set $kong_proxy_mode 'websocket';

        # keep connections open for a brief window after the content handler exits
        #
        # this increases the likeliness of being able to perform a clean
        # shutdown when terminating a WebSocket session under abnormal
        # conditions (i.e. NGINX shutdown or other proxy-initiated close)
        lingering_close always;
        lingering_time 5s;
        lingering_timeout 1s;

        lua_check_client_abort on;

        body_filter_by_lua_block {;}

        access_by_lua_block {
          Kong.ws_handshake()
        }

        content_by_lua_block {
          Kong.ws_proxy()
        }

        log_by_lua_block {
          Kong.ws_close()
        }
    }


    location = /kong_buffered_http {
        internal;
        default_type         '';
        set $kong_proxy_mode 'http';

        rewrite_by_lua_block       {
          -- ngx.localtion.capture will create a new nginx request,
          -- so the upstream ssl-related info attached to the `r` gets lost.
          -- we need to re-set them here to the new nginx request.
          local ctx = ngx.ctx
          local upstream_ssl = require("kong.runloop.upstream_ssl")

          upstream_ssl.set_service_ssl(ctx)
          upstream_ssl.fallback_upstream_client_cert(ctx)
        }
        access_by_lua_block        {;}
        header_filter_by_lua_block {;}
        body_filter_by_lua_block   {;}
        log_by_lua_block           {;}

        proxy_http_version 1.1;
        proxy_set_header      TE                 $upstream_te;
        proxy_set_header      Host               $upstream_host;
        proxy_set_header      Upgrade            $upstream_upgrade;
        proxy_set_header      Connection         $upstream_connection;
        proxy_set_header      X-Forwarded-For    $upstream_x_forwarded_for;
        proxy_set_header      X-Forwarded-Proto  $upstream_x_forwarded_proto;
        proxy_set_header      X-Forwarded-Host   $upstream_x_forwarded_host;
        proxy_set_header      X-Forwarded-Port   $upstream_x_forwarded_port;
        proxy_set_header      X-Forwarded-Path   $upstream_x_forwarded_path;
        proxy_set_header      X-Forwarded-Prefix $upstream_x_forwarded_prefix;
        proxy_set_header      X-Real-IP          $remote_addr;
> if enabled_headers_upstream["X-Kong-Request-Id"] then
        proxy_set_header      X-Kong-Request-Id  $kong_request_id;
> end
        proxy_pass_header     Server;
        proxy_pass_header     Date;
        proxy_ssl_name        $upstream_host;
        proxy_ssl_server_name on;
> if client_ssl then
        proxy_ssl_certificate ${{CLIENT_SSL_CERT}};
        proxy_ssl_certificate_key ${{CLIENT_SSL_CERT_KEY}};
> end
        proxy_pass            $upstream_scheme://kong_upstream$upstream_uri;
    }

    location = /kong_error_handler {
        internal;
        default_type                 '';

        uninitialized_variable_warn  off;

        rewrite_by_lua_block {;}
        access_by_lua_block  {;}

        content_by_lua_block {
            Kong.handle_error()
        }
    }
}
> end -- (role == "traditional" or role == "data_plane") and #proxy_listeners > 0

> if (role == "control_plane" or role == "traditional") and #admin_listeners > 0 and #admin_gui_listeners > 0 then
server {
    server_name kong_gui;
> for i = 1, #admin_gui_listeners do
    listen $(admin_gui_listeners[i].listener);
> end

> if admin_gui_ssl_enabled then
> for i = 1, #admin_gui_ssl_cert do
    ssl_certificate     $(admin_gui_ssl_cert[i]);
    ssl_certificate_key $(admin_gui_ssl_cert_key[i]);
> end
    ssl_protocols ${{ADMIN_GUI_SSL_PROTOCOLS}};
> end

    client_max_body_size 10m;
    client_body_buffer_size 10m;

    types {
        text/html                             html htm shtml;
        text/css                              css;
        text/xml                              xml;
        image/gif                             gif;
        image/jpeg                            jpeg jpg;
        application/javascript                js;
        application/json                      json;
        image/png                             png;
        image/tiff                            tif tiff;
        image/x-icon                          ico;
        image/x-jng                           jng;
        image/x-ms-bmp                        bmp;
        image/svg+xml                         svg svgz;
        image/webp                            webp;
    }

    access_log ${{ADMIN_GUI_ACCESS_LOG}};
    error_log ${{ADMIN_GUI_ERROR_LOG}};

    gzip on;
    gzip_types text/plain text/css application/json application/javascript;

    include nginx-kong-gui-include.conf;
}
> end -- of the (role == "control_plane" or role == "traditional") and #admin_listeners > 0 and #admin_gui_listeners > 0


> if (role == "control_plane" or role == "traditional") and portal then
server {
    server_name kong_portal_gui;
> for i = 1, #portal_gui_listeners do
    listen $(portal_gui_listeners[i].listener);
> end

    access_log ${{PORTAL_GUI_ACCESS_LOG}};
    error_log ${{PORTAL_GUI_ERROR_LOG}} ${{LOG_LEVEL}};

> if portal_gui_ssl_enabled then
> for i = 1, #portal_gui_ssl_cert do
    ssl_certificate     $(portal_gui_ssl_cert[i]);
    ssl_certificate_key $(portal_gui_ssl_cert_key[i]);
> end
    ssl_protocols ${{PORTAL_GUI_SSL_PROTOCOLS}};
> end

    client_max_body_size 10m;
    client_body_buffer_size 10m;
    log_not_found off;

    types {
      text/html                             html htm shtml;
      text/css                              css;
      text/xml                              xml;
      image/gif                             gif;
      image/jpeg                            jpeg jpg;
      application/javascript                js;
      application/json                      json;
      image/png                             png;
      image/tiff                            tif tiff;
      image/x-icon                          ico;
      image/x-jng                           jng;
      image/x-ms-bmp                        bmp;
      image/svg+xml                         svg svgz;
      image/webp                            webp;
    }

    gzip on;
    gzip_types text/plain text/css application/json application/javascript;

    location ^~ /__legacy {
        root portal;

        header_filter_by_lua_block {
            ngx.header["server"] = nil
        }

        expires 90d;
        add_header Cache-Control 'public';
        add_header X-Frame-Options 'sameorigin';
        add_header X-XSS-Protection '1; mode=block';
        add_header X-Content-Type-Options 'nosniff';
        etag off;
    }

    location ~* \.(jpg|jpeg|png|gif|ico|css|ttf|js|svg)$ {
        root portal;

        header_filter_by_lua_block {
            ngx.header["server"] = nil
        }

        content_by_lua_block {
            Kong.serve_portal_gui({
                acah = "Content-Type",
            })
        }

        expires 90d;
        add_header Cache-Control 'public';
        add_header Content-Security-Policy "default-src 'none'";
        add_header X-Frame-Options 'sameorigin';
        add_header X-XSS-Protection '1; mode=block';
        add_header X-Content-Type-Options 'nosniff';
        etag off;
    }


    location / {
        root portal;
        default_type text/html;

        header_filter_by_lua_block {
            ngx.header["server"] = nil
        }

        content_by_lua_block {
            Kong.serve_portal_gui({
                acah = "Content-Type",
            })
        }

        add_header Cache-Control 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0';
        add_header Access-Control-Allow-Headers 'Content-Type';
        add_header Access-Control-Allow-Origin '*';
        etag off;
    }

    location /robots.txt {
        header_filter_by_lua_block {
            ngx.header["server"] = nil
        }

        return 200 'User-agent: *\nDisallow: /';
    }
}

> if #portal_api_listeners > 0 and portal_api_listen then

server {
    server_name portal_api;
> for i = 1, #portal_api_listeners do
    listen $(portal_api_listeners[i].listener);
> end

    access_log ${{PORTAL_API_ACCESS_LOG}};
    error_log ${{PORTAL_API_ERROR_LOG}} ${{LOG_LEVEL}};

    client_max_body_size 10m;
    client_body_buffer_size 10m;

> if portal_api_ssl_enabled then
> for i = 1, #portal_api_ssl_cert do
    ssl_certificate     $(portal_api_ssl_cert[i]);
    ssl_certificate_key $(portal_api_ssl_cert_key[i]);
> end
    ssl_protocols ${{PORTAL_API_SSL_PROTOCOLS}};

    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_prefer_server_ciphers on;
> if ssl_ciphers then
    ssl_ciphers ${{SSL_CIPHERS}};
> end
> end

    location / {
        default_type application/json;
        content_by_lua_block {
            Kong.serve_portal_api({
                acah = "Content-Type",
            })
        }
    }

    location /robots.txt {
        return 200 'User-agent: *\nDisallow: /';
    }
}
> end
> end

> if (role == "control_plane" or role == "traditional") and #admin_listeners > 0 then
server {
    charset UTF-8;
    server_name kong_admin;
> for _, entry in ipairs(admin_listeners) do
    listen $(entry.listener);
> end

    access_log ${{ADMIN_ACCESS_LOG}};
    error_log  ${{ADMIN_ERROR_LOG}} ${{LOG_LEVEL}};

    real_ip_header     ${{REAL_IP_HEADER}};
    real_ip_recursive  ${{REAL_IP_RECURSIVE}};
> for i = 1, #trusted_ips do
    set_real_ip_from   $(trusted_ips[i]);
> end

> if admin_ssl_enabled then
> for i = 1, #admin_ssl_cert do
    ssl_certificate     $(admin_ssl_cert[i]);
    ssl_certificate_key $(admin_ssl_cert_key[i]);
> end
    ssl_session_cache   shared:AdminSSL:10m;
> end

    # injected nginx_admin_* directives
> for _, el in ipairs(nginx_admin_directives) do
    $(el.name) $(el.value);
> end

    location / {
        default_type application/json;
        content_by_lua_block {
            Kong.admin_content({
                acah = "Content-Type, ${{RBAC_AUTH_HEADER}}, Kong-Request-Type, Cache-Control",
            })
        }

        log_by_lua_block {
            local audit_log = require "kong.enterprise_edition.audit_log"
            audit_log.admin_log_handler()
            require("kong.tracing").flush()
        }
        header_filter_by_lua_block {
            Kong.admin_header_filter()
        }
    }

    location /robots.txt {
        return 200 'User-agent: *\nDisallow: /';
    }
}
> end -- (role == "control_plane" or role == "traditional") and #admin_listeners > 0

> if #status_listeners > 0 then
server {
    charset UTF-8;
    server_name kong_status;
> for _, entry in ipairs(status_listeners) do
    listen $(entry.listener);
> end

    access_log ${{STATUS_ACCESS_LOG}};
    error_log  ${{STATUS_ERROR_LOG}} ${{LOG_LEVEL}};

> if status_ssl_enabled then
> for i = 1, #status_ssl_cert do
    ssl_certificate     $(status_ssl_cert[i]);
    ssl_certificate_key $(status_ssl_cert_key[i]);
> end
    ssl_session_cache   shared:StatusSSL:1m;
> end

    # injected nginx_status_* directives
> for _, el in ipairs(nginx_status_directives) do
    $(el.name) $(el.value);
> end

    location / {
        default_type application/json;
        content_by_lua_block {
            Kong.status_content()
        }
        header_filter_by_lua_block {
            Kong.status_header_filter()
        }
    }

    location /robots.txt {
        return 200 'User-agent: *\nDisallow: /';
    }
}
> end

> if #debug_listeners > 0 or debug_listen_local then
server {
    server_name kong_debug;
> if #debug_listeners > 0 then
> for _, entry in ipairs(debug_listeners) do
    listen $(entry.listener);
> end
> end

> if debug_listen_local then
    listen unix:${{PREFIX}}/kong_debug.sock;
> end

    access_log ${{DEBUG_ACCESS_LOG}};
    error_log  ${{DEBUG_ERROR_LOG}} ${{LOG_LEVEL}};

> if #debug_listeners > 0 then
> if status_ssl_enabled then
> for i = 1, #status_ssl_cert do
    ssl_certificate     $(debug_ssl_cert[i]);
    ssl_certificate_key $(debug_ssl_cert_key[i]);
> end
    ssl_session_cache   shared:DebugSSL:1m;
> end
> end

    # injected nginx_debug_* directives
> for _, el in ipairs(nginx_debug_directives) do
    $(el.name) $(el.value);
> end

    location / {
        default_type application/json;
        content_by_lua_block {
            Kong.debug_content()
        }
        header_filter_by_lua_block {
            Kong.debug_header_filter()
        }
    }

    location /robots.txt {
        return 200 'User-agent: *\nDisallow: /';
    }
}
> end

> if role == "control_plane" then
server {
    charset UTF-8;
    server_name kong_cluster_listener;
> for _, entry in ipairs(cluster_listeners) do
    listen $(entry.listener) ssl;
> end

    access_log ${{ADMIN_ACCESS_LOG}};
    error_log  ${{ADMIN_ERROR_LOG}} ${{LOG_LEVEL}};

> if cluster_mtls == "shared" then
    ssl_verify_client   optional_no_ca;
> else
    ssl_verify_client   on;
    ssl_client_certificate ${{CLUSTER_CA_CERT}};
    ssl_verify_depth     4;
> end
    ssl_certificate     ${{CLUSTER_CERT}};
    ssl_certificate_key ${{CLUSTER_CERT_KEY}};
    ssl_session_cache   shared:ClusterSSL:10m;

    location = /v1/outlet {
        content_by_lua_block {
            Kong.serve_cluster_listener()
        }
    }
}
> end -- role == "control_plane"

> if role == "control_plane" then
server {
    server_name kong_cluster_telemetry_listener;
> for _, entry in ipairs(cluster_telemetry_listeners) do
    listen $(entry.listener) ssl;
> end

    access_log off;

> if cluster_mtls == "shared" then
    ssl_verify_client   optional_no_ca;
> else
    ssl_verify_client   on;
    ssl_client_certificate ${{CLUSTER_CA_CERT}};
    ssl_verify_depth     4;
> end
    ssl_certificate     ${{CLUSTER_CERT}};
    ssl_certificate_key ${{CLUSTER_CERT_KEY}};
    ssl_session_cache   shared:ClusterSSL:10m;

    location = /v1/ingest {
        content_by_lua_block {
            Kong.serve_cluster_telemetry_listener()
        }
    }
}
> end -- role == "control_plane"

server {
    charset UTF-8;
    server_name kong_worker_events;
    listen unix:${{PREFIX}}/worker_events.sock;
    access_log off;
    location / {
        content_by_lua_block {
          require("resty.events.compat").run()
        }
    }
}
]]
