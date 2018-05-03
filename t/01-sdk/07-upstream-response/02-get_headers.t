use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: upstream.response.get_headers() returns a table
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

            ngx.arg[1] = "type: " .. type(sdk.upstream.response.get_headers())
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
type: table
--- no_error_log
[error]



=== TEST 2: upstream.response.get_headers() returns upstream response headers
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location / {
            content_by_lua_block {
                ngx.header.Foo = "Hello"
                ngx.header.Bar = "World"
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

            local headers = sdk.upstream.response.get_headers()

            ngx.arg[1] = "Foo: " .. headers.Foo .. "\n" ..
                         "Bar: " .. headers.Bar .. "\n" ..
                         "Accept: " .. table.concat(headers.Accept, ", ")


            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
Foo: Hello
Bar: World
Accept: application/json, text/html
--- no_error_log
[error]



=== TEST 3: upstream.response.get_headers() returns upstream response headers with case-insensitive metatable
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

            local headers = sdk.upstream.response.get_headers()

            ngx.arg[1] = "X-Foo-Header: " .. headers["X-Foo-Header"] .. "\n" ..
                         "x-Foo-header: " .. headers["x-Foo-header"] .. "\n" ..
                         "x_foo_header: " .. headers["x_foo_header"] .. "\n" ..
                         "x_Foo_header: " .. headers["x_Foo_header"]

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



=== TEST 4: upstream.response.get_headers() fetches 100 headers max by default
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location / {
            default_type '';
            content_by_lua_block {
                for i = 1, 200 do
                    ngx.header["X-Header-" .. i] = "test"
                end
            }
        }
    }
--- config
    location = /t {
        default_type '';
        proxy_pass http://unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil
        }

        body_filter_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local headers = sdk.upstream.response.get_headers()

            local n = 0

            for k in pairs(headers) do
                if string.lower(string.sub(k, 1, 1)) == "x" then
                    n = n + 1
                end
            end

            ngx.arg[1] = ngx.arg[1] .. "number of headers fetched: " .. n
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
number of headers fetched: 100
--- no_error_log
[error]



=== TEST 5: upstream.response.get_headers() fetches max_headers argument
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location / {
            default_type '';
            content_by_lua_block {
                for i = 1, 100 do
                    ngx.header["X-Header-" .. i] = "test"
                end
            }
        }
    }
--- config
    location = /t {
        default_type  '';
        proxy_pass http://unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil
        }

        body_filter_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local headers = sdk.upstream.response.get_headers(60)

            local n = 0

            for k in pairs(headers) do
                if string.lower(string.sub(k, 1, 1)) == "x" then
                    n = n + 1
                end
            end

            ngx.arg[1] = ngx.arg[1] .. "number of headers fetched: " .. n
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
number of headers fetched: 60
--- no_error_log
[error]



=== TEST 6: upstream.response.get_headers() raises error when trying to fetch with max_headers invalid value
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

            local _, err = pcall(sdk.upstream.response.get_headers, "invalid")

            ngx.arg[1] = "error: " .. err
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
error: max_headers must be a number
--- no_error_log
[error]



=== TEST 7: upstream.response.get_headers() raises error when trying to fetch with max_headers < 1
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

            local _, err = pcall(sdk.upstream.response.get_headers, 0)

            ngx.arg[1] = "error: " .. err
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
error: max_headers must be >= 1
--- no_error_log
[error]



=== TEST 8: upstream.response.get_headers() raises error when trying to fetch with max_headers > 1000
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

            local _, err = pcall(sdk.upstream.response.get_headers, 1001)

            ngx.arg[1] = "error: " .. err
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
error: max_headers must be <= 1000
--- no_error_log
[error]
