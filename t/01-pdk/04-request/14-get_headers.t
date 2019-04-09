use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_headers() returns a table
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("type: ", type(pdk.request.get_headers()))
        }
    }
--- request
GET /t
--- response_body
type: table
--- no_error_log
[error]



=== TEST 2: request.get_headers() returns request headers
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local headers = pdk.request.get_headers()
            ngx.say("Foo: ", headers.foo)
            ngx.say("Bar: ", headers.bar)
            ngx.say("Accept: ", table.concat(headers.accept, ", "))
        }
    }
--- request
GET /t
--- more_headers
Foo: Hello
Bar: World
Accept: application/json
Accept: text/html
--- response_body
Foo: Hello
Bar: World
Accept: application/json, text/html
--- no_error_log
[error]



=== TEST 3: request.get_headers() returns request headers with case-insensitive metatable
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local headers = pdk.request.get_headers()
            ngx.say("X-Foo-Header: ", headers["X-Foo-Header"])
            ngx.say("x-Foo-header: ", headers["x-Foo-header"])
            ngx.say("x_foo_header: ", headers.x_foo_header)
            ngx.say("x_Foo_header: ", headers.x_Foo_header)
        }
    }
--- request
GET /t
--- more_headers
X-Foo-Header: Hello
--- response_body
X-Foo-Header: Hello
x-Foo-header: Hello
x_foo_header: Hello
x_Foo_header: Hello
--- no_error_log
[error]



=== TEST 4: request.get_headers() fetches 100 headers max by default
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        rewrite_by_lua_block {
            for i = 1, 200 do
                ngx.req.set_header("X-Header-" .. i, "test")
            end
        }

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local headers = pdk.request.get_headers()

            local n = 0

            for _ in pairs(headers) do
                n = n + 1
            end

            ngx.say("number of headers fetched: ", n)
        }
    }
--- request
GET /t
--- response_body
number of headers fetched: 100
--- no_error_log
[error]



=== TEST 5: request.get_headers() fetches max_headers argument
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        rewrite_by_lua_block {
            for i = 1, 100 do
                ngx.req.set_header("X-Header-" .. i, "test")
            end
        }

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local headers = pdk.request.get_headers(60)

            local n = 0

            for _ in pairs(headers) do
                n = n + 1
            end

            ngx.say("number of headers fetched: ", n)
        }
    }
--- request
GET /t
--- response_body
number of headers fetched: 60
--- no_error_log
[error]



=== TEST 6: request.get_headers() raises error when trying to fetch with max_headers invalid value
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local _, err = pcall(pdk.request.get_headers, "invalid")

            ngx.say("error: ", err)
        }
    }
--- request
GET /t
--- response_body
error: max_headers must be a number
--- no_error_log
[error]



=== TEST 7: request.get_headers() raises error when trying to fetch with max_headers < 1
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local _, err = pcall(pdk.request.get_headers, 0)

            ngx.say("error: ", err)
        }
    }
--- request
GET /t
--- response_body
error: max_headers must be >= 1
--- no_error_log
[error]



=== TEST 8: request.get_headers() raises error when trying to fetch with max_headers > 1000
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local _, err = pcall(pdk.request.get_headers, 1001)

            ngx.say("error: ", err)
        }
    }
--- request
GET /t
--- response_body
error: max_headers must be <= 1000
--- no_error_log
[error]
