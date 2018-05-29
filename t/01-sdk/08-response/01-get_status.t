use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: response.get_status() returns a number
--- config
    location /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.ctx.type = "type: " .. type(sdk.response.get_status())
        }

        body_filter_by_lua_block {
            ngx.arg[1] = ngx.ctx.type
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
type: number
--- no_error_log
[error]



=== TEST 2: response.get_status() returns 200 from service
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location / {
            return 200;
        }
    }
--- config
    location /t {
        proxy_pass http://unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil
        }

        body_filter_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.arg[1] = "status: " .. sdk.response.get_status()
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
status: 200
--- no_error_log
[error]



=== TEST 3: response.get_status() returns 404 from service
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location / {
            return 404;
        }
    }
--- config
    location /t {
        proxy_pass http://unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil
        }

        body_filter_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.arg[1] = "status: " .. sdk.response.get_status()
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- error_code: 404
--- response_body chop
status: 404
--- no_error_log
[error]



=== TEST 4: response.get_status() returns last status code set
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location / {
            content_by_lua_block {
                ngx.status = 203
            }
        }
    }
--- config
    location /t {
        rewrite_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.status = 201
        }

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.status = 202
        }

        proxy_pass http://unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            assert(sdk.response.get_status() == 203, "203 ~=" .. tostring(sdk.response.get_status()))
            ngx.status = 204
            assert(sdk.response.get_status() == 204, "204 ~=" .. tostring(sdk.response.get_status()))
        }

        body_filter_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            assert(sdk.response.get_status() == 204, "204 ~=" .. tostring(sdk.response.get_status()))
        }

        log_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            assert(sdk.response.get_status() == 204, "204 ~=" .. tostring(sdk.response.get_status()))
        }
    }
--- request
GET /t
--- error_code: 204
--- response_body chop
--- no_error_log
[error]



=== TEST 5: response.get_headers() errors on non-supported phases
--- http_config
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local phases = {
                "set",
                "rewrite",
                "access",
                "content",
                "log",
                "header_filter",
                "body_filter",
                "timer",
                "init_worker",
                "balancer",
                "ssl_cert",
                "ssl_session_store",
                "ssl_session_fetch",
            }

            local data = {}
            local i = 0

            for _, phase in ipairs(phases) do
                ngx.get_phase = function()
                    return phase
                end

                local ok, err = pcall(sdk.response.get_status)
                if not ok then
                    i = i + 1
                    data[i] = err
                end
            end

            ngx.ctx.data = table.concat(data, "\n")
        }

        body_filter_by_lua_block {
            ngx.arg[1] = ngx.ctx.data
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body chop
kong.response.get_status is disabled in the context of set
kong.response.get_status is disabled in the context of rewrite
kong.response.get_status is disabled in the context of access
kong.response.get_status is disabled in the context of content
kong.response.get_status is disabled in the context of timer
kong.response.get_status is disabled in the context of init_worker
kong.response.get_status is disabled in the context of balancer
kong.response.get_status is disabled in the context of ssl_cert
kong.response.get_status is disabled in the context of ssl_session_store
kong.response.get_status is disabled in the context of ssl_session_fetch
--- no_error_log
[error]
