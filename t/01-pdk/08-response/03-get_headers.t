use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: response.get_headers() returns a table
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.ctx.data = "type: " .. type(pdk.response.get_headers())
        }

        body_filter_by_lua_block {
            ngx.arg[1] = ngx.ctx.data
            ngx.arg[2] = true
        }

    }
--- request
GET /t
--- response_body chop
type: table
--- no_error_log
[error]



=== TEST 2: response.get_headers() returns service response headers
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

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
}
--- config
    location = /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil
        }

        body_filter_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local headers = pdk.response.get_headers()

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



=== TEST 3: response.get_headers() returns service response headers with case-insensitive metatable
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location / {
            content_by_lua_block {
                ngx.header["X-Foo-Header"] = "Hello"
            }
        }
    }
}
--- config
    location = /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil
        }

        body_filter_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local headers = pdk.response.get_headers()

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



=== TEST 4: response.get_headers() fetches 100 headers max by default
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type '';
        content_by_lua_block {
            for i = 1, 200 do
                ngx.header["X-Header-" .. i] = "test"
            end
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local headers = pdk.response.get_headers()

            local n = 0

            for k in pairs(headers) do
                if string.lower(string.sub(k, 1, 1)) == "x" then
                    n = n + 1

                elseif string.lower(k) == "connection" then
                    n = n + 1
                end
            end

            ngx.ctx.n = n
        }

        body_filter_by_lua_block {
            ngx.arg[1] = "number of headers fetched: " .. ngx.ctx.n
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
number of headers fetched: 100
--- no_error_log
[error]



=== TEST 5: response.get_headers() returns error when truncating
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type '';
        content_by_lua_block {
            for i = 1, 200 do
                ngx.header["X-Header-" .. i] = "test"
            end
        }

        body_filter_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local headers, err = pdk.response.get_headers()
            if err then
                ngx.arg[1] = err
                ngx.arg[2] = true
            end
        }
    }
--- request
GET /t
--- response_body chop
truncated
--- no_error_log
[error]



=== TEST 6: response.get_headers() fetches max_headers argument
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type  '';
        content_by_lua_block {
            for i = 1, 100 do
                ngx.header["X-Header-" .. i] = "test"
            end
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local headers = pdk.response.get_headers(60)

            local n = 0

            for k in pairs(headers) do
                if string.lower(string.sub(k, 1, 1)) == "x" then
                    n = n + 1

                elseif string.lower(k) == "connection" then
                    n = n + 1
                end
            end

            ngx.ctx.n = n
        }

        body_filter_by_lua_block {
            ngx.arg[1] = "number of headers fetched: " .. ngx.ctx.n
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
number of headers fetched: 60
--- no_error_log
[error]



=== TEST 7: response.get_headers() raises error when trying to fetch with max_headers invalid value
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local ok, err = pcall(pdk.response.get_headers, "invalid")
            if not ok then
                ngx.ctx.err = err
            end
        }

        body_filter_by_lua_block {
            ngx.arg[1] = "error: " .. ngx.ctx.err
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
error: max_headers must be a number
--- no_error_log
[error]



=== TEST 8: response.get_headers() raises error when trying to fetch with max_headers < 1
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local ok, err = pcall(pdk.response.get_headers, 0)
            if not ok then
                ngx.ctx.err = err
            end
        }

        body_filter_by_lua_block {
            ngx.arg[1] = "error: " .. ngx.ctx.err
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
error: max_headers must be >= 1
--- no_error_log
[error]



=== TEST 9: response.get_headers() raises error when trying to fetch with max_headers > 1000
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local ok, err = pcall(pdk.response.get_headers, 1001)
            if not ok then
                ngx.ctx.err = err
            end
        }

        body_filter_by_lua_block {
            ngx.arg[1] = "error: " .. ngx.ctx.err
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
error: max_headers must be <= 1000
--- no_error_log
[error]



=== TEST 10: response.get_headers() returns not-only service headers
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location / {
            content_by_lua_block {
                ngx.header["X-Service-Header"] = "test"
            }
        }
    }
}
--- config
    location = /t {
        access_by_lua_block {
            ngx.header["X-Non-Service-Header"] = "test"
        }

        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil
        }

        body_filter_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local headers = pdk.response.get_headers()

            ngx.arg[1] = "X-Service-Header: "     .. headers["X-Service-Header"]      .. "\n" ..
                         "X-Non-Service-Header: " .. headers["X-Non-Service-Header"]

            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
X-Service-Header: test
X-Non-Service-Header: test
--- no_error_log
[error]
