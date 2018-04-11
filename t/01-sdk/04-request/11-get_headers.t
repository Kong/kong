use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 2);

run_tests();

__DATA__

=== TEST 1: request.get_headers() returns a table
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("type: ", type(sdk.request.get_headers()))
        }
    }
--- request
GET /t
--- response_body
type: table
--- no_error_log
[error]



=== TEST 2: request.get_headers() returns request headers
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local headers = sdk.request.get_headers()
            ngx.say("Foo: ", headers.foo)
            ngx.say("Bar: ", headers.bar)
        }
    }
--- request
GET /t
--- more_headers
Foo: Hello
Bar: World
--- response_body
Foo: Hello
Bar: World
--- no_error_log
[error]



=== TEST 3: request.get_headers() returns request headers with case-insensitive metatable
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local headers = sdk.request.get_headers()
            ngx.say("X-Foo-Header: ", headers["X-Foo-Header"])
            ngx.say("x-Foo-header: ", headers["x-Foo-header"])
            ngx.say("x_foo_header: ", headers.x_foo_header)
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
--- no_error_log
[error]



=== TEST 4: request.get_headers() fetches 100 headers max by default
--- config
    location = /t {
        access_by_lua_block {
            for i = 1, 200 do
                ngx.req.set_header("X-Header-" .. i, "test")
            end
        }

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local headers = sdk.request.get_headers()

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
--- config
    location = /t {
        access_by_lua_block {
            for i = 1, 100 do
                ngx.req.set_header("X-Header-" .. i, "test")
            end
        }

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local headers = sdk.request.get_headers(60)

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



=== TEST 6: request.get_headers() fetches all headers when max_headers = 0
--- config
    location = /t {
        access_by_lua_block {
            for i = 1, 200 do
                ngx.req.set_header("X-Header-" .. i, "test")
            end
        }

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local headers = sdk.request.get_headers(0)

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
number of headers fetched: 102
--- no_error_log
[error]



=== TEST 7: request.get_headers() fetches all headers when max_headers = 0
--- config
    location = /t {
        access_by_lua_block {
            for i = 1, 200 do
                ngx.req.set_header("X-Header-" .. i, "test")
            end
        }

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local headers = sdk.request.get_headers(0)

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
number of headers fetched: 102
--- no_error_log
[error]
