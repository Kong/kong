use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use File::Spec;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_method() returns request method as string 1/2
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("method: ", sdk.request.get_method())
        }
    }
--- request
GET /t
--- response_body
method: GET
--- no_error_log
[error]



=== TEST 2: request.get_method() returns request method as string 2/2
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("method: ", sdk.request.get_method())
        }
    }
--- request
POST /t
--- response_body
method: POST
--- no_error_log
[error]
