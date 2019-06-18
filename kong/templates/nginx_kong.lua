return [[
charset UTF-8;

> if anonymous_reports then
${{SYSLOG_REPORTS}}
> end

error_log ${{PROXY_ERROR_LOG}} ${{LOG_LEVEL}};

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

client_max_body_size ${{CLIENT_MAX_BODY_SIZE}};
proxy_ssl_server_name on;
underscores_in_headers on;

lua_package_path '${{LUA_PACKAGE_PATH}};;';
lua_package_cpath '${{LUA_PACKAGE_CPATH}};;';
lua_socket_pool_size ${{LUA_SOCKET_POOL_SIZE}};
lua_max_running_timers 4096;
lua_max_pending_timers 16384;
lua_shared_dict kong                5m;
lua_shared_dict kong_db_cache       ${{MEM_CACHE_SIZE}};
> if database == "off" then
lua_shared_dict kong_db_cache_2     ${{MEM_CACHE_SIZE}};
> end
lua_shared_dict kong_db_cache_miss 12m;
> if database == "off" then
lua_shared_dict kong_db_cache_miss_2 12m;
> end
lua_shared_dict kong_locks          8m;
lua_shared_dict kong_process_events 5m;
lua_shared_dict kong_cluster_events 5m;
lua_shared_dict kong_vitals_counters 50m;
lua_shared_dict kong_vitals_lists   1m;
lua_shared_dict kong_healthchecks   5m;
lua_shared_dict kong_rate_limiting_counters 12m;
lua_shared_dict kong_reports_apis            1m;
lua_shared_dict kong_reports_consumers       10m;
lua_shared_dict kong_reports_routes          1m;
lua_shared_dict kong_reports_services        1m;
> if database == "cassandra" then
lua_shared_dict kong_cassandra      5m;
> end
lua_socket_log_errors off;
> if lua_ssl_trusted_certificate then
lua_ssl_trusted_certificate '${{LUA_SSL_TRUSTED_CERTIFICATE}}';
> end
lua_ssl_verify_depth ${{LUA_SSL_VERIFY_DEPTH}};

# injected nginx_http_* directives
> for _, el in ipairs(nginx_http_directives)  do
$(el.name) $(el.value);
> end

init_by_lua_block {
    Kong = require 'kong'
    Kong.init()
}

init_worker_by_lua_block {
    Kong.init_worker()
}


> if #proxy_listeners > 0 then
upstream kong_upstream {
    server 0.0.0.1;
    balancer_by_lua_block {
        Kong.balancer()
    }
> if upstream_keepalive > 0 then
    keepalive ${{UPSTREAM_KEEPALIVE}};
> end
}

server {
    server_name kong;
> for i = 1, #proxy_listeners do
    listen $(proxy_listeners[i].listener);
> end
    error_page 400 404 408 411 412 413 414 417 494 /kong_error_handler;
    error_page 500 502 503 504 /kong_error_handler;

    access_log ${{PROXY_ACCESS_LOG}};
    error_log ${{PROXY_ERROR_LOG}} ${{LOG_LEVEL}};

    client_body_buffer_size ${{CLIENT_BODY_BUFFER_SIZE}};

> if proxy_ssl_enabled then
    ssl_certificate ${{SSL_CERT}};
    ssl_certificate_key ${{SSL_CERT_KEY}};
    ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
    ssl_certificate_by_lua_block {
        Kong.ssl_certificate()
    }

    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ${{SSL_CIPHERS}};
> end

> if client_ssl then
    proxy_ssl_certificate ${{CLIENT_SSL_CERT}};
    proxy_ssl_certificate_key ${{CLIENT_SSL_CERT_KEY}};
> end

    real_ip_header     ${{REAL_IP_HEADER}};
    real_ip_recursive  ${{REAL_IP_RECURSIVE}};
> for i = 1, #trusted_ips do
    set_real_ip_from   $(trusted_ips[i]);
> end

    # injected nginx_proxy_* directives
> for _, el in ipairs(nginx_proxy_directives)  do
    $(el.name) $(el.value);
> end

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
        set $set_request_id     $request_id;

        rewrite_by_lua_block {
            Kong.rewrite()
        }

        access_by_lua_block {
            Kong.access()
        }

        proxy_http_version 1.1;
        proxy_set_header   TE                $upstream_te;
        proxy_set_header   Host              $upstream_host;
        proxy_set_header   Upgrade           $upstream_upgrade;
        proxy_set_header   Connection        $upstream_connection;
        proxy_set_header   X-Forwarded-For   $upstream_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $upstream_x_forwarded_proto;
        proxy_set_header   X-Forwarded-Host  $upstream_x_forwarded_host;
        proxy_set_header   X-Forwarded-Port  $upstream_x_forwarded_port;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_pass_header  Server;
        proxy_pass_header  Date;
        proxy_ssl_name     $upstream_host;
        proxy_pass         $upstream_scheme://kong_upstream$upstream_uri;

        header_filter_by_lua_block {
            Kong.header_filter()
        }

        body_filter_by_lua_block {
            Kong.body_filter()
        }

        log_by_lua_block {
            Kong.log()
        }
    }

    location = /kong_error_handler {
        internal;
        uninitialized_variable_warn off;

        content_by_lua_block {
            Kong.handle_error()
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
    }
}
> end


> if #admin_listen > 0 and #admin_gui_listeners > 0 then
server {
    server_name kong_gui;
> for i = 1, #admin_gui_listeners do
    listen $(admin_gui_listeners[i].listener);
> end

> if admin_gui_ssl_enabled then
    ssl_certificate ${{ADMIN_GUI_SSL_CERT}};
    ssl_certificate_key ${{ADMIN_GUI_SSL_CERT_KEY}};
    ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
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

    gzip on;
    gzip_types text/plain text/css application/json application/javascript;

    location ~* \.(jpg|jpeg|png|gif|ico|css|ttf|js)$ {
        root gui;

        expires 90d;
        add_header Cache-Control 'public';
        add_header X-Frame-Options 'sameorigin';
        add_header X-XSS-Protection '1; mode=block';
        add_header X-Content-Type-Options 'nosniff';
        etag off;
    }

    location / {
        root gui;

        try_files $uri /index.html;

        add_header Cache-Control 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0';
        add_header X-Frame-Options 'sameorigin';
        add_header X-XSS-Protection '1; mode=block';
        add_header X-Content-Type-Options 'nosniff';
        etag off;

        access_log ${{ADMIN_GUI_ACCESS_LOG}};
        error_log ${{ADMIN_GUI_ERROR_LOG}};
    }

    location /robots.txt {
        return 200 'User-agent: *\nDisallow: /';
    }

    location = /kconfig.js {
        root gui;
        expires -1;
    }
}
> end


> if portal then
server {
    server_name kong_portal_gui;
> for i = 1, #portal_gui_listeners do
    listen $(portal_gui_listeners[i].listener);
> end

> if portal_gui_ssl_enabled then
    ssl_certificate ${{PORTAL_GUI_SSL_CERT}};
    ssl_certificate_key ${{PORTAL_GUI_SSL_CERT_KEY}};
    ssl_protocols TLSv1.1 TLSv1.2;
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

    location ~* \.(jpg|jpeg|png|gif|ico|css|ttf|js)$ {
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

        access_log logs/portal_gui_access.log;
        error_log logs/portal_gui_error.log;
    }

    location /robots.txt {
        header_filter_by_lua_block {
            ngx.header["server"] = nil
        }

        return 200 'User-agent: *\nDisallow: /';
    }
}


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
    ssl_certificate ${{PORTAL_API_SSL_CERT}};
    ssl_certificate_key ${{PORTAL_API_SSL_CERT_KEY}};
    ssl_protocols TLSv1.1 TLSv1.2;

    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ${{SSL_CIPHERS}};
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


> if #admin_listeners > 0 then
server {
    server_name kong_admin;
> for i = 1, #admin_listeners do
    listen $(admin_listeners[i].listener);
> end

    access_log ${{ADMIN_ACCESS_LOG}};
    error_log ${{ADMIN_ERROR_LOG}} ${{LOG_LEVEL}};

    client_max_body_size 10m;
    client_body_buffer_size 10m;

    real_ip_header     ${{REAL_IP_HEADER}};
    real_ip_recursive  ${{REAL_IP_RECURSIVE}};
> for i = 1, #trusted_ips do
    set_real_ip_from   $(trusted_ips[i]);
> end

> if admin_ssl_enabled then
    ssl_certificate ${{ADMIN_SSL_CERT}};
    ssl_certificate_key ${{ADMIN_SSL_CERT_KEY}};
    ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;

    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ${{SSL_CIPHERS}};
> end

    # injected nginx_admin_* directives
> for _, el in ipairs(nginx_admin_directives)  do
    $(el.name) $(el.value);
> end

    location / {
        default_type application/json;
        content_by_lua_block {
            Kong.serve_admin_api({
                acah = "Content-Type, ${{RBAC_AUTH_HEADER}}, Kong-Request-Type",
            })
        }

        log_by_lua_block {
            local audit_log = require "kong.enterprise_edition.audit_log"
            audit_log.admin_log_handler()
            require("kong.tracing").flush()
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
> end
]]
