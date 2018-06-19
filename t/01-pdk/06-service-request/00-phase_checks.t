use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

plan tests => repeat_each() * (blocks() * 2);

run_tests();

__DATA__

=== TEST 1: verify phase checking in kong.service.request
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_HTML_DIR}/nginx.sock;

        location / {
            return 200;
        }
    }

    init_worker_by_lua_block {

        phases = require("kong.pdk.private.phases").phases

        phase_check_module = "service.request"
        phase_check_data = {
            {
                method        = "set_scheme",
                args          = { "http" },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = "forced false",
                access        = true,
                header_filter = "forced false",
                body_filter   = "forced false",
                log           = "forced false",
            }, {
                method        = "set_method",
                args          = { "GET" },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = "forced false",
                body_filter   = "forced false",
                log           = "forced false",
            }, {
                method        = "set_path",
                args          = { "/" },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = "forced false",
                access        = true,
                header_filter = "forced false",
                body_filter   = "forced false",
                log           = "forced false",
            }, {
                method        = "set_raw_query",
                args          = { "foo=bar&baz=bla" },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = "forced false",
                body_filter   = "forced false",
                log           = "forced false",
            }, {
                method        = "set_query",
                args          = { { foo = "bar", baz = "bla" } },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = "forced false",
                body_filter   = "forced false",
                log           = "forced false",
            }, {
                method        = "set_header",
                args          = { "X-Foo", "bar" },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = "forced false",
                body_filter   = "forced false",
                log           = "forced false",
            }, {
                method        = "add_header",
                args          = { "X-Foo", "bar" },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = "forced false",
                body_filter   = "forced false",
                log           = "forced false",
            }, {
                method        = "clear_header",
                args          = { "X-Foo" },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = "forced false",
                body_filter   = "forced false",
                log           = "forced false",
            }, {
                method        = "set_headers",
                args          = { { ["X-Foo"] = "bar" } },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = "forced false",
                body_filter   = "forced false",
                log           = "forced false",
            }, {
                method        = "set_raw_body",
                args          = { "foo" },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = false,
                body_filter   = false,
                log           = false,
            }, {
                method        = "set_body",
                args          = { { foo = "bar" }, "application/json" },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = true,
                access        = true,
                header_filter = false,
                body_filter   = false,
                log           = false,
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
        proxy_pass http://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
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
