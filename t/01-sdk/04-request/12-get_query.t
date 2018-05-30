use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_query() returns a table
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("type: ", type(sdk.request.get_query()))
        }
    }
--- request
GET /t
--- response_body
type: table
--- no_error_log
[error]



=== TEST 2: request.get_query() returns request query arguments
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local args = sdk.request.get_query()
            ngx.say("Foo: ", args.Foo)
            ngx.say("Bar: ", args.Bar)
            ngx.say("Accept: ", table.concat(args.Accept, ", "))
        }
    }
--- request
GET /t?Foo=Hello&Bar=World&Accept=application%2Fjson&Accept=text%2Fhtml
--- response_body
Foo: Hello
Bar: World
Accept: application/json, text/html
--- no_error_log
[error]



=== TEST 3: request.get_query() returns request query arguments case-sensitive
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local args = sdk.request.get_query()
            ngx.say("Foo: ", args.Foo)
            ngx.say("foo: ", args.foo)
            ngx.say("fOO: ", args.fOO)
        }
    }
--- request
GET /t?Foo=Hello&foo=World&fOO=Too
--- response_body
Foo: Hello
foo: World
fOO: Too
--- no_error_log
[error]



=== TEST 4: request.get_query() fetches 100 query arguments by default
--- config
    location = /t {
        rewrite_by_lua_block {
            local args = {}
            for i = 1, 200 do
                args["arg-" .. i] = "test"
            end
            ngx.req.set_uri_args(args)
        }

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local args = sdk.request.get_query()

            local n = 0

            for _ in pairs(args) do
                n = n + 1
            end

            ngx.say("number of query arguments fetched: ", n)
        }
    }
--- request
GET /t
--- response_body
number of query arguments fetched: 100
--- no_error_log
[error]



=== TEST 5: request.get_query() fetches max_args argument
--- config
    location = /t {
        rewrite_by_lua_block {
            local args = {}
            for i = 1, 100 do
                args["arg-" .. i] = "test"
            end
            ngx.req.set_uri_args(args)
        }

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local headers = sdk.request.get_query(60)

            local n = 0

            for _ in pairs(headers) do
                n = n + 1
            end

            ngx.say("number of query arguments fetched: ", n)
        }
    }
--- request
GET /t
--- response_body
number of query arguments fetched: 60
--- no_error_log
[error]



=== TEST 6: request.get_query() raises error when trying to fetch with max_args invalid value
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local _, err = pcall(sdk.request.get_query, "invalid")

            ngx.say("error: ", err)
        }
    }
--- request
GET /t
--- response_body
error: max_args must be a number
--- no_error_log
[error]



=== TEST 7: request.get_query() raises error when trying to fetch with max_args < 1
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local _, err = pcall(sdk.request.get_query, 0)

            ngx.say("error: ", err)
        }
    }
--- request
GET /t
--- response_body
error: max_args must be >= 1
--- no_error_log
[error]



=== TEST 8: request.get_query() raises error when trying to fetch with max_args > 1000
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local _, err = pcall(sdk.request.get_query, 1001)

            ngx.say("error: ", err)
        }
    }
--- request
GET /t
--- response_body
error: max_args must be <= 1000
--- no_error_log
[error]
