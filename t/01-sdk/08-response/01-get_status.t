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
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.print("type: " .. type(sdk.response.get_status()))
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


set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua*, body_filter_by_lua*, log_by_lua*



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

            assert(sdk.response.get_status() == 0, "0 ~=" .. tostring(sdk.response.get_status()))
            ngx.status = 201
            assert(sdk.response.get_status() == 201, "201 ~=" .. tostring(sdk.response.get_status()))
        }

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            assert(sdk.response.get_status() == 201, "201 ~=" .. tostring(sdk.response.get_status()))
            ngx.status = 202
            assert(sdk.response.get_status() == 202, "202 ~=" .. tostring(sdk.response.get_status()))
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
--- no_error_log
[error]
