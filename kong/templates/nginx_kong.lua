return [[
charset UTF-8;
server_tokens off;

error_log ${{PROXY_ERROR_LOG}} ${{LOG_LEVEL}};

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

lua_shared_dict kong                        5m;
lua_shared_dict kong_locks                  8m;
lua_shared_dict kong_healthchecks           5m;
lua_shared_dict kong_process_events         5m;
lua_shared_dict kong_cluster_events         5m;
lua_shared_dict kong_rate_limiting_counters 12m;
lua_shared_dict kong_core_db_cache          ${{MEM_CACHE_SIZE}};
lua_shared_dict kong_core_db_cache_miss     12m;
lua_shared_dict kong_db_cache               ${{MEM_CACHE_SIZE}};
lua_shared_dict kong_db_cache_miss          12m;
> if database == "off" then
lua_shared_dict kong_core_db_cache_2        ${{MEM_CACHE_SIZE}};
lua_shared_dict kong_core_db_cache_miss_2   12m;
lua_shared_dict kong_db_cache_2             ${{MEM_CACHE_SIZE}};
lua_shared_dict kong_db_cache_miss_2        12m;
> end
> if database == "cassandra" then
lua_shared_dict kong_cassandra              5m;
> end

underscores_in_headers on;
> if ssl_ciphers then
ssl_ciphers ${{SSL_CIPHERS}};
> end

# injected nginx_http_* directives
> for _, el in ipairs(nginx_http_directives) do
$(el.name) $(el.value);
> end

init_by_lua_block {
    Kong = require 'kong'
    Kong.init()
}

init_worker_by_lua_block {
    Kong.init_worker()
}

> if (role == "traditional" or role == "data_plane") and #proxy_listeners > 0 then
# Load variable indexes
lua_kong_load_var_index $args;
lua_kong_load_var_index $bytes_sent;
lua_kong_load_var_index $content_type;
lua_kong_load_var_index $host;
lua_kong_load_var_index $http_authorization;
lua_kong_load_var_index $http_connection;
lua_kong_load_var_index $http_host;
lua_kong_load_var_index $http_kong_debug;
lua_kong_load_var_index $http_proxy;
lua_kong_load_var_index $http_proxy_connection;
lua_kong_load_var_index $http_te;
lua_kong_load_var_index $http_upgrade;
lua_kong_load_var_index $http_x_forwarded_for;
lua_kong_load_var_index $http_x_forwarded_host;
lua_kong_load_var_index $http_x_forwarded_path;
lua_kong_load_var_index $http_x_forwarded_port;
lua_kong_load_var_index $http_x_forwarded_prefix;
lua_kong_load_var_index $http_x_forwarded_proto;
lua_kong_load_var_index $https;
lua_kong_load_var_index $http2;
lua_kong_load_var_index $is_args;
lua_kong_load_var_index $realip_remote_addr;
lua_kong_load_var_index $realip_remote_port;
lua_kong_load_var_index $remote_addr;
lua_kong_load_var_index $remote_port;
lua_kong_load_var_index $request;
lua_kong_load_var_index $request_length;
lua_kong_load_var_index $request_method;
lua_kong_load_var_index $request_time;
lua_kong_load_var_index $request_uri;
lua_kong_load_var_index $scheme;
lua_kong_load_var_index $server_addr;
lua_kong_load_var_index $server_port;
lua_kong_load_var_index $ssl_cipher;
lua_kong_load_var_index $ssl_client_raw_cert;
lua_kong_load_var_index $ssl_client_verify;
lua_kong_load_var_index $ssl_protocol;
lua_kong_load_var_index $ssl_server_name;
lua_kong_load_var_index $upstream_http_connection;
lua_kong_load_var_index $upstream_http_trailer;
lua_kong_load_var_index $upstream_http_upgrade;
lua_kong_load_var_index $upstream_status;

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

    access_log ${{PROXY_ACCESS_LOG}};
    error_log  ${{PROXY_ERROR_LOG}} ${{LOG_LEVEL}};

> if proxy_ssl_enabled then
> for i = 1, #ssl_cert do
    ssl_certificate     $(ssl_cert[i]);
    ssl_certificate_key $(ssl_cert_key[i]);
> end
    ssl_session_cache   shared:SSL:10m;
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

    location = /kong_buffered_http {
        internal;
        default_type         '';
        set $kong_proxy_mode 'http';

        rewrite_by_lua_block       {;}
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

> if (role == "control_plane" or role == "traditional") and #admin_listeners > 0 then
server {
    server_name kong_admin;
> for _, entry in ipairs(admin_listeners) do
    listen $(entry.listener);
> end

    access_log ${{ADMIN_ACCESS_LOG}};
    error_log  ${{ADMIN_ERROR_LOG}} ${{LOG_LEVEL}};

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
            Kong.admin_content()
        }
        header_filter_by_lua_block {
            Kong.admin_header_filter()
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
> end -- (role == "control_plane" or role == "traditional") and #admin_listeners > 0

> if #status_listeners > 0 then
server {
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

> if role == "control_plane" then
server {
    server_name kong_cluster_listener;
> for _, entry in ipairs(cluster_listeners) do
    listen $(entry.listener) ssl;
> end

    access_log ${{ADMIN_ACCESS_LOG}};

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
]]
