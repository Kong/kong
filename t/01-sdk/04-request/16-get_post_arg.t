use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_post_arg() returns value of given argument
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
--- no_error_log
[error]



=== TEST 2: request.get_post_arg() returns values as string when defined
--- config
    location = /t {

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say(type(sdk.request.get_post_arg("a")))
            ngx.say(type(sdk.request.get_post_arg("b")))
            ngx.say(type(sdk.request.get_post_arg("c")))
            ngx.say(type(sdk.request.get_post_arg("d")))
            ngx.say(type(sdk.request.get_post_arg("e")))
        }
    }
--- request
POST /t
a=3&b=true&c=false&d=nil&e=string
--- response_body
string
string
string
string
string
--- no_error_log
[error]



=== TEST 3: request.get_post_arg() returns true for args without value
--- config
    location = /t {

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say(sdk.request.get_post_arg("c"))
            ngx.say(type(sdk.request.get_post_arg("c")))
        }
    }
--- request
POST /t
a=3&b=4&c
--- response_body
true
boolean
--- no_error_log
[error]



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
--- no_error_log
[error]



=== TEST 5: request.get_post_arg() returns first encountered value for repeated args even if it has no value
--- config
    location = /t {

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say(sdk.request.get_post_arg("param"))
            ngx.say(type(sdk.request.get_post_arg("param")))
        }
    }
--- request
POST /t
param&param=bar&param=baz
--- response_body
true
boolean
--- no_error_log
[error]



=== TEST 6: request.get_post_arg() raises an error when given a non-string param
--- config
    location = /t {

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = pcall(sdk.request.get_post_arg, 1)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
name must be a string
--- no_error_log
[error]



=== TEST 7: request.get_post_arg() returns nil for non-existing args
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
--- no_error_log
[error]



=== TEST 8: request.get_post_arg() returns nil for when value of Content-Length header is less than 1
--- config
    location = /t {

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say(sdk.request.get_post_arg("a"))
        }
    }
--- request
POST /t
a=3
--- more_headers
Content-Length: 0
--- response_body
nil
--- no_error_log
[error]
