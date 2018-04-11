use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 2);

run_tests();

__DATA__



=== TEST 2: request.get_post_arg() when giv
--- config
    location = /t {

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say(sdk.request.get_post_arg("b"))
        }
    }
--- request
POST /t
a=3&b=4&c
--- response_body
4

=== TEST 3: request.get_post_arg() returns true for args without value
--- config
    location = /t {

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say(sdk.request.get_post_arg("c"))
        }
    }
--- request
POST /t
a=3&b=4&c
--- response_body
true

=== TEST 4: request.get_post_arg() returns first encountered value for repeated args
--- config
    location = /t {

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say(sdk.request.get_post_arg("param"))
        }
    }
--- request
POST /t
param=foo&param=bar&param=baz
--- response_body
foo

=== TEST 1: request.get_post_arg() raises an error when given a non-string param
--- config
    location = /t {

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say(sdk.request.get_post_arg(1))
        }
    }
--- request
GET /t
--- response_body eval
qr/.+500 Internal Server Error/
--- error_code: 500

=== TEST 1: request.get_post_arg() returns nil for non-existing args
--- config
    location = /t {

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say(sdk.request.get_post_arg("x"))
        }
    }
--- request
POST /t
a=3
--- response_body
nil

