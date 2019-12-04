use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 2);

run_tests();

__DATA__

=== TEST 1: verify phase checking in kong.response
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location / {
            return 200;
        }
    }

    init_worker_by_lua_block {

        phases = require("kong.pdk.private.phases").phases

        phase_check_module = "response"
        phase_check_data = {
            {
                method        = "get_status",
                args          = { },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = "forced false",
                access        = false,
                header_filter = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "get_header",
                args          = { "X-Foo" },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = "forced false",
                access        = false,
                header_filter = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "get_headers",
                args          = { },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = "forced false",
                access        = false,
                header_filter = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "get_headers",
                args          = { 100 },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = "forced false",
                access        = false,
                header_filter = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "set_status",
                args          = { 200 },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = false,
                log           = false,
                admin_api     = true,
            }, {
                method        = "set_header",
                args          = { "X-Foo", "bar" },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = false,
                log           = false,
                admin_api     = true,
            }, {
                method        = "add_header",
                args          = { "X-Foo", "bar" },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = false,
                log           = false,
                admin_api     = true,
            }, {
                method        = "clear_header",
                args          = { "X-Foo" },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = false,
                log           = false,
                admin_api     = true,
            }, {
                method        = "set_headers",
                args          = { { ["X-Foo"] = "bar" } },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = false,
                log           = false,
                admin_api     = true,
            }, {
                method        = "exit",
                args          = { 200, "Hello, world" },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = "pending",
                body_filter   = false,
                log           = false,
                admin_api     = true,
            }, {
                method        = "get_source",
                args          = { },
                init_worker   = "forced false",
                certificate   = "pending",
                rewrite       = "forced false",
                access        = "forced false",
                header_filter = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }
        }

        phase_check_functions(phases.init_worker)
    }

    #ssl_certificate_by_lua_block {
    #    phase_check_functions(phases.certificate)
    #}
}
--- config
    location /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;
        set $upstream_uri '/t';
        set $upstream_scheme 'http';

        rewrite_by_lua_block {
            phase_check_functions(phases.rewrite)
        }

        access_by_lua_block {
            phase_check_functions(phases.access)
        }

        header_filter_by_lua_block {
            phase_check_functions(phases.header_filter)
        }

        body_filter_by_lua_block {
            phase_check_functions(phases.body_filter)
        }

        log_by_lua_block {
            phase_check_functions(phases.log)
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 2: verify phase checking for kong.response.exit with table, failing phases
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location / {
            return 200;
        }
    }

    init_worker_by_lua_block {

        phases = require("kong.pdk.private.phases").phases

        phase_check_module = "response"
        phase_check_data = {
            {
                method        = "exit",
                args          = { 200, { message = "Hello" } },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = "pending",
                body_filter   = false,
                log           = false,
                admin_api     = true,
            },

        }

        phase_check_functions(phases.init_worker, true)
    }

    #ssl_certificate_by_lua_block {
    #    phase_check_functions(phases.certificate)
    #}
}
--- config
    location /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;
        set $upstream_uri '/t';
        set $upstream_scheme 'http';

        header_filter_by_lua_block {
            phase_check_functions(phases.header_filter, true)
            -- reset Content-Length after partial execution with
            -- phase checks disabled
            ngx.header["Content-Length"] = 0
        }

        body_filter_by_lua_block {
            phase_check_functions(phases.body_filter, true)
        }

        log_by_lua_block {
            phase_check_functions(phases.log, true)
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 3: verify phase checking for kong.response.exit and with no body, failing phases
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location / {
            return 200;
        }
    }

    init_worker_by_lua_block {

        phases = require("kong.pdk.private.phases").phases

        phase_check_module = "response"
        phase_check_data = {
            {
                method        = "exit",
                args          = { 200 },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = false,
                log           = false,
                admin_api     = true,
            },

        }

        phase_check_functions(phases.init_worker, true)
    }

    #ssl_certificate_by_lua_block {
    #    phase_check_functions(phases.certificate)
    #}
}
--- config
    location /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;
        set $upstream_uri '/t';
        set $upstream_scheme 'http';

        header_filter_by_lua_block {
            phase_check_functions(phases.header_filter, true)
            -- reset Content-Length after partial execution with
            -- phase checks disabled
            ngx.header["Content-Length"] = 0
        }

        body_filter_by_lua_block {
            phase_check_functions(phases.body_filter, true)
        }

        log_by_lua_block {
            phase_check_functions(phases.log, true)
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 4: verify phase checking for kong.response.exit, rewrite, with plain string
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location / {
            return 200;
        }
    }

    init_worker_by_lua_block {

        phases = require("kong.pdk.private.phases").phases

        phase_check_module = "response"
        phase_check_data = {
            {
                method        = "exit",
                args          = { 200, "Hello" },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = false,
                body_filter   = false,
                log           = false,
            },
        }
    }
}
--- config
    location /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;
        set $upstream_uri '/t';
        set $upstream_scheme 'http';

        rewrite_by_lua_block {
            phase_check_functions(phases.rewrite, true)
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 5: verify phase checking for kong.response.exit, rewrite, with tables
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location / {
            return 200;
        }
    }

    init_worker_by_lua_block {

        phases = require("kong.pdk.private.phases").phases

        phase_check_module = "response"
        phase_check_data = {
            {
                method        = "exit",
                args          = { 200, { message = "Hello" }, { ["X-Foo"] = "bar" } },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = false,
                body_filter   = false,
                log           = false,
                admin_api     = true,
            },
        }
    }
}
--- config
    location /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;
        set $upstream_uri '/t';
        set $upstream_scheme 'http';

        rewrite_by_lua_block {
            phase_check_functions(phases.rewrite, true)
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 6: verify phase checking for kong.response.exit, rewrite, with no body
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location / {
            return 200;
        }
    }

    init_worker_by_lua_block {

        phases = require("kong.pdk.private.phases").phases

        phase_check_module = "response"
        phase_check_data = {
            {
                method        = "exit",
                args          = { 200 },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = false,
                log           = false,
            },
        }
    }
}
--- config
    location /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;
        set $upstream_uri '/t';
        set $upstream_scheme 'http';

        rewrite_by_lua_block {
            phase_check_functions(phases.rewrite, true)
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 7: verify phase checking for kong.response.exit, access, with plain string
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location / {
            return 200;
        }
    }

    init_worker_by_lua_block {

        phases = require("kong.pdk.private.phases").phases

        phase_check_module = "response"
        phase_check_data = {
            {
                method        = "exit",
                args          = { 200, "Hello" },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = false,
                body_filter   = false,
                log           = false,
                admin_api     = true,
            },
        }
    }
}
--- config
    location /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;
        set $upstream_uri '/t';
        set $upstream_scheme 'http';

        access_by_lua_block {
            phase_check_functions(phases.access, true)
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 8: verify phase checking for kong.response.exit, access, with tables
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location / {
            return 200;
        }
    }

    init_worker_by_lua_block {

        phases = require("kong.pdk.private.phases").phases

        phase_check_module = "response"
        phase_check_data = {
            {
                method        = "exit",
                args          = { 200, { message = "Hello" }, { ["X-Foo"] = "bar" } },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = false,
                body_filter   = false,
                log           = false,
                admin_api     = true,
            },
        }
    }
}
--- config
    location /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;
        set $upstream_uri '/t';
        set $upstream_scheme 'http';

        access_by_lua_block {
            phase_check_functions(phases.access, true)
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 9: verify phase checking for kong.response.exit, access, with no body
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location / {
            return 200;
        }
    }

    init_worker_by_lua_block {

        phases = require("kong.pdk.private.phases").phases

        phase_check_module = "response"
        phase_check_data = {
            {
                method        = "exit",
                args          = { 200 },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = false,
                log           = false,
                admin_api     = true,
            },
        }
    }
}
--- config
    location /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;
        set $upstream_uri '/t';
        set $upstream_scheme 'http';

        access_by_lua_block {
            phase_check_functions(phases.access, true)
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 10: verify phase checking for kong.response.exit, admin_api, with plain string
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location / {
            return 200;
        }
    }

    init_worker_by_lua_block {

        phases = require("kong.pdk.private.phases").phases

        phase_check_module = "response"
        phase_check_data = {
            {
                method        = "exit",
                args          = { 200, "Hello" },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = false,
                body_filter   = false,
                log           = false,
                admin_api     = true,
            },
        }
    }
}
--- config
    location /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;
        set $upstream_uri '/t';
        set $upstream_scheme 'http';

        access_by_lua_block {
            phase_check_functions(phases.admin_api, true)
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 11: verify phase checking for kong.response.exit, admin_api, with tables
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location / {
            return 200;
        }
    }

    init_worker_by_lua_block {

        phases = require("kong.pdk.private.phases").phases

        phase_check_module = "response"
        phase_check_data = {
            {
                method        = "exit",
                args          = { 200, { message = "Hello" }, { ["X-Foo"] = "bar" } },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = false,
                body_filter   = false,
                log           = false,
                admin_api     = true,
            },
        }
    }
}
--- config
    location /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;
        set $upstream_uri '/t';
        set $upstream_scheme 'http';

        access_by_lua_block {
            phase_check_functions(phases.admin_api, true)
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 12: verify phase checking for kong.response.exit, admin_api, with no body
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location / {
            return 200;
        }
    }

    init_worker_by_lua_block {

        phases = require("kong.pdk.private.phases").phases

        phase_check_module = "response"
        phase_check_data = {
            {
                method        = "exit",
                args          = { 200 },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = false,
                log           = false,
                admin_api     = true,
            },
        }
    }
}
--- config
    location /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;
        set $upstream_uri '/t';
        set $upstream_scheme 'http';

        access_by_lua_block {
            phase_check_functions(phases.admin_api, true)
        }
    }
--- request
GET /t
--- no_error_log
[error]
