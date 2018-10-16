use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 2);

run_tests();

__DATA__

=== TEST 1: verify phase checking in kong.request
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

        phase_check_module = "request"
        phase_check_data = {
            {
                method        = "get_scheme",
                args          = {},
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "get_host",
                args          = {},
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "get_port",
                args          = {},
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "get_forwarded_scheme",
                args          = {},
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "get_forwarded_host",
                args          = {},
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "get_forwarded_port",
                args          = {},
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "get_http_version",
                args          = {},
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "get_method",
                args          = {},
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "get_path",
                args          = {},
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "get_path_with_query",
                args          = {},
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "get_raw_query",
                args          = {},
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "get_query_arg",
                args          = { "foo" },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "get_query",
                args          = {},
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "get_query",
                args          = { 100 },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "get_header",
                args          = { "Host" },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "get_headers",
                args          = {},
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "get_headers",
                args          = { 100 },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "get_raw_body",
                args          = {},
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = false,
                body_filter   = false,
                log           = false,
                admin_api     = true,
            }, {
                method        = "get_body",
                args          = { "application/json" },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = false,
                body_filter   = false,
                log           = false,
                admin_api     = true,
            }, {
                method        = "get_body",
                args          = { "application/x-www-form-urlencoded" },
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
            phase_check_functions(phases.admin_api)
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
