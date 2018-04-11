use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_port() returns server port
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()
            --sdk.init(nil, "ip")

            ngx.say("port: ", sdk.request.get_port())
        }
    }
--- request
GET /t
--- response_body_like chomp
port: \d+
--- no_error_log
[error]



=== TEST 2: request.get_port() returns a number
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()
            --sdk.init(nil, "ip")

            ngx.say("port type: ", type(sdk.request.get_port()))
        }
    }
--- request
GET /t
--- response_body
port type: number
--- no_error_log
[error]
