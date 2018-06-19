use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

plan tests => repeat_each() * (blocks() * 2);

run_tests();

__DATA__

=== TEST 1: verify phase checking in kong.service
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

        -- mock kong.runloop.balancer
        package.loaded["kong.runloop.balancer"] = {
            get_upstream_by_name = function(name)
                if name == "my_upstream" then
                    return {}
                end
            end
        }

        phases = require("kong.pdk.private.phases").phases

        phase_check_module = "service"
        phase_check_data = {
            {
                method        = "set_upstream",
                args          = { "my_upstream" },
                init_worker   = "forced false",
                certificate   = "pending",
                rewrite       = "forced false",
                access        = true,
                header_filter = "forced false",
                body_filter   = "forced false",
                log           = "forced false",
            }, {
                method        = "set_target",
                args          = { "example.com", 8000 },
                init_worker   = false,
                certificate   = "pending",
                rewrite       = "forced false",
                access        = true,
                header_filter = "forced false",
                body_filter   = "forced false",
                log           = "forced false",
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
        set $upstream_host 'example.com';
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
