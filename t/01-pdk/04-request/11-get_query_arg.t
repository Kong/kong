use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_query_arg() returns first query arg when multiple is given with same name
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("Foo: ", pdk.request.get_query_arg("Foo"))
        }
    }
--- request
GET /t?Foo=1&Foo=2
--- response_body
Foo: 1
--- no_error_log
[error]



=== TEST 2: request.get_query_arg() returns values from case-sensitive table
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("Foo: ", pdk.request.get_query_arg("Foo"))
            ngx.say("foo: ", pdk.request.get_query_arg("foo"))
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
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("Bar: ", pdk.request.get_query_arg("Bar"))
        }
    }
--- request
GET /t?Foo=1
--- response_body
Bar: nil
--- no_error_log
[error]



=== TEST 4: request.get_query_arg() returns true when query argument has no value
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("Foo: ", pdk.request.get_query_arg("Foo"))
        }
    }
--- request
GET /t?Foo
--- response_body
Foo: true
--- no_error_log
[error]



=== TEST 5: request.get_query_arg() returns empty string when query argument's value is empty
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("Foo: '", pdk.request.get_query_arg("Foo"), "'")
        }
    }
--- request
GET /t?Foo=
--- response_body
Foo: ''
--- no_error_log
[error]



=== TEST 6: request.get_query_arg() returns nil when requested query arg does not fit in max_args
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        rewrite_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local args = {}
            for i = 1, 100 do
                args["arg-" .. i] = "test"
            end

            local args = ngx.encode_args(args)
            args = args .. "&arg-101=test"

            ngx.req.set_uri_args(args)
        }

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("argument value: ", pdk.request.get_query_arg("arg-101"))
        }
    }
--- request
GET /t
--- response_body
argument value: nil
--- no_error_log
[error]



=== TEST 7: request.get_query_arg() raises error when trying to fetch with invalid argument
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local _, err = pcall(pdk.request.get_query_arg)

            ngx.say("error: ", err)
        }
    }
--- request
GET /t
--- response_body
error: query argument name must be a string
--- no_error_log
[error]
