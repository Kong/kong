use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: upstream.response.get_header() returns first header when multiple is given with same name
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location / {
            content_by_lua_block {
                ngx.header.Accept = {
                    "application/json",
                    "text/html",
                }
            }
        }
    }
--- config
    location = /t {
        proxy_pass http://unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil
        }

        body_filter_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.arg[1] = "content type header value: " .. sdk.upstream.response.get_header("Accept")
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
content type header value: application/json
--- no_error_log
[error]



=== TEST 2: upstream.response.get_header() returns values from case-insensitive metatable
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location / {
            content_by_lua_block {
                ngx.header["X-Foo-Header"] = "Hello"
            }
        }
    }
--- config
    location = /t {
        proxy_pass http://unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil
        }

        body_filter_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.arg[1] = "X-Foo-Header: " .. sdk.upstream.response.get_header("X-Foo-Header") .. "\n" ..
                         "x-Foo-header: " .. sdk.upstream.response.get_header("x-Foo-header") .. "\n" ..
                         "x_foo_header: " .. sdk.upstream.response.get_header("x_foo_header") .. "\n" ..
                         "x_Foo_header: " .. sdk.upstream.response.get_header("x_Foo_header")

            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
X-Foo-Header: Hello
x-Foo-header: Hello
x_foo_header: Hello
x_Foo_header: Hello
--- no_error_log
[error]



=== TEST 3: upstream.response.get_header() returns nil when header is missing
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location / {
            return 200;
        }
    }
--- config
    location = /t {
        proxy_pass http://unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil
        }

        body_filter_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.arg[1] = "X-Missing: " .. type(sdk.upstream.response.get_header("X-Missing"))
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
X-Missing: nil
--- no_error_log
[error]



=== TEST 4: upstream.response.get_header() returns nil when response header does not fit in default max_headers
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location / {
            content_by_lua_block {
                for i = 1, 100 do
                    ngx.header["X-Header-" .. i] = "test"
                end

                ngx.header["Accept"] = "text/html"
            }
        }
    }

--- config
    location = /t {
        proxy_pass http://unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil
        }

        body_filter_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.arg[1] = "accept header value: " .. type(sdk.upstream.response.get_header("Accept"))
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
accept header value: nil
--- no_error_log
[error]



=== TEST 5: upstream.response.get_header() raises error when trying to fetch with invalid argument
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location / {
            return 200;
        }
    }
--- config
    location = /t {
        proxy_pass http://unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil
        }

        body_filter_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local _, err = pcall(sdk.upstream.response.get_header)

            ngx.arg[1] = "error: " .. err
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
error: name must be a string
--- no_error_log
[error]
