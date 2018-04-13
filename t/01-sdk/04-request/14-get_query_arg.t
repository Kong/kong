use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_query_arg() returns first query arg when multiple is given with same name
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("Foo: ", sdk.request.get_query_arg("Foo"))
        }
    }
--- request
GET /t?Foo=1&Foo=2
--- response_body
Foo: 1
--- no_error_log
[error]



=== TEST 2: request.get_query_arg() returns values from case-sensitive table
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("Foo: ", sdk.request.get_query_arg("Foo"))
            ngx.say("foo: ", sdk.request.get_query_arg("foo"))
        }
    }
--- request
GET /t?Foo=1&foo=2
--- response_body
Foo: 1
foo: 2
--- no_error_log
[error]



=== TEST 3: request.get_query_arg() returns nil when query argument is missing
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("Bar: ", sdk.request.get_query_arg("Bar"))
        }
    }
--- request
GET /t?Foo=1
--- response_body
Bar: nil
--- no_error_log
[error]



=== TEST 4: request.get_query_arg() returns true when query argument has no value
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("Foo: ", sdk.request.get_query_arg("Foo"))
        }
    }
--- request
GET /t?Foo
--- response_body
Foo: true
--- no_error_log
[error]



=== TEST 5: request.get_query_arg() returns empty string when query argument's value is empty
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("Foo: '", sdk.request.get_query_arg("Foo"), "'")
        }
    }
--- request
GET /t?Foo=
--- response_body
Foo: ''
--- no_error_log
[error]



=== TEST 6: request.get_query_arg() returns nil when requested query arg does not fit in max_args
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local args = {}
            for i = 1, 100 do
                args["arg-" .. i] = "test"
            end

            local args = ngx.encode_args(args)
            args = args .. "&arg-101=test"

            ngx.req.set_uri_args(args)
        }

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("argument value: ", sdk.request.get_query_arg("arg-101"))
        }
    }
--- request
GET /t
--- response_body
argument value: nil
--- no_error_log
[error]



=== TEST 7: request.get_query_arg() raises error when trying to fetch with invalid argument
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local _, err = pcall(sdk.request.get_query_arg)

            ngx.say("error: ", err)
        }
    }
--- request
GET /t
--- response_body
error: name must be a string
--- no_error_log
[error]
