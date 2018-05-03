use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: upstream.response.get_status() returns a number
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location / {
            return 200;
        }
    }
--- config
    location /t {
        proxy_set_header Host "";
        proxy_pass http://unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil
        }

        body_filter_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.arg[1] = "type: " .. type(sdk.upstream.response.get_status())
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
type: number
--- no_error_log
[error]



=== TEST 2: upstream.response.get_status() returns 200
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location / {
            return 200;
        }
    }
--- config
    location /t {
        proxy_set_header Host "";
        proxy_pass http://unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil
        }

        body_filter_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.arg[1] = "status: " .. sdk.upstream.response.get_status()
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
status: 200
--- no_error_log
[error]



=== TEST 3: upstream.response.get_status() returns 404
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

            ngx.arg[1] = "status: " .. sdk.upstream.response.get_status()
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
