use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_http_version() returns request http version 1.0
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("version: ", sdk.request.get_http_version())
        }
    }
--- request
GET /t HTTP/1.0
--- response_body
version: 1
--- no_error_log
[error]



=== TEST 2: request.get_http_version() returns request http version 1.1
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("version: ", sdk.request.get_http_version())
        }
    }
--- request
GET /t
--- response_body
version: 1.1
--- no_error_log
[error]



=== TEST 3: request.get_http_version() returns number
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("type: ", type(sdk.request.get_http_version()))
        }
    }
--- request
GET /t
--- response_body
type: number
--- no_error_log
[error]
