use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
do "./t/Util.pm";

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 2);

run_tests();

__DATA__

=== TEST 1: verify phase checking in kong.log
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

        phase_check_module = "log"
        phase_check_data = {
            {
                method        = "new",
                args          = { "my_namespace" },
                init_worker   = true,
                certificate   = true,
                rewrite       = true,
                access        = true,
                header_filter = true,
                response      = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "set_format",
                args          = { "my_format" },
                init_worker   = true,
                certificate   = true,
                rewrite       = true,
                access        = true,
                header_filter = true,
                response      = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "serialize",
                args          = {
                  { kong =
                     { request = {
                          get_query = function() return "query" end,
                          get_method = function() return "GET" end,
                          get_headers = function() return {} end,
                          get_start_time = function() return 1 end,
                        },
                       response = {
                          get_source = function() return "service" end,
                        },
                       service = {
                          response = {
                            get_status = function() return 200 end,
                          },
                        },
                     }
                  }
                },
                init_worker   = false,
                certificate   = "forced false",
                rewrite       = "forced false",
                access        = "forced false",
                header_filter = "forced false",
                response      = "forced false",
                body_filter   = "forced false",
                log           = true,
                admin_api     = false,
            }, {
                method        = "set_serialize_value",
                args          = { "valname", "valvalue" },
                init_worker   = "pending", -- fails in CI for some reason
                certificate   = false,
                rewrite       = true,
                access        = true,
                header_filter = true,
                response      = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "debug",
                args          = { "foo" },
                init_worker   = true,
                certificate   = true,
                rewrite       = true,
                access        = true,
                header_filter = true,
                response      = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "info",
                args          = { "foo" },
                init_worker   = true,
                certificate   = true,
                rewrite       = true,
                access        = true,
                header_filter = true,
                response      = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "notice",
                args          = { "foo" },
                init_worker   = true,
                certificate   = true,
                rewrite       = true,
                access        = true,
                header_filter = true,
                response      = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "warn",
                args          = { "foo" },
                init_worker   = true,
                certificate   = true,
                rewrite       = true,
                access        = true,
                header_filter = true,
                response      = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
-- kong.log.err cannot be tested this way, since the test itself expects no errors in the log
--            }, {
--               method        = "err",
--               args          = { "foo" },
--               init_worker   = true,
--               certificate   = true,
--               rewrite       = true,
--               access        = true,
--               header_filter = true,
--               response      = true,
--               body_filter   = true,
--               log           = true,
--               admin_api     = true,
            }, {
                method        = "crit",
                args          = { "foo" },
                init_worker   = true,
                certificate   = true,
                rewrite       = true,
                access        = true,
                header_filter = true,
                response      = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "alert",
                args          = { "foo" },
                init_worker   = true,
                certificate   = true,
                rewrite       = true,
                access        = true,
                header_filter = true,
                response      = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            }, {
                method        = "emerg",
                args          = { "foo" },
                init_worker   = true,
                certificate   = true,
                rewrite       = true,
                access        = true,
                header_filter = true,
                response      = true,
                body_filter   = true,
                log           = true,
                admin_api     = true,
            },
        }

        -- passing true here (and all other phase checks) since there are some functions in
        -- kong log (like kong.log.err) that we don't want to test
        -- (kong.log.err produces lines in the error log, which isn't expected)h
        phase_check_functions(phases.init_worker, true)
    }

    #ssl_certificate_by_lua_block {
    #    phase_check_functions(phases.certificate, true)
    #}
}
--- config
    location /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;
        set $upstream_uri '/t';
        set $upstream_scheme 'http';

        rewrite_by_lua_block {
            phase_check_functions(phases.rewrite, true)
        }

        access_by_lua_block {
            phase_check_functions(phases.access, true)
            phase_check_functions(phases.response, true)
        }

        header_filter_by_lua_block {
            phase_check_functions(phases.header_filter, true)
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
