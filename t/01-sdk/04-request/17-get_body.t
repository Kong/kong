use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use File::Spec;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_body() returns empty strings for empty bodies
--- config
    location = /t {

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("body: '", sdk.request:get_body(), "'")
        }
    }
--- request
GET /t
--- response_body
body: ''
--- no_error_log
[error]



=== TEST 2: request.get_body() returns empty string when Content-Length header is less than 1
--- config
    location = /t {

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("body: '", sdk.request:get_body(), "'")
        }
    }
--- request
POST /t
ignored
--- more_headers
Content-Length: 0
--- response_body
body: ''
--- no_error_log
[error]



=== TEST 3: request.get_body() returns body string when Content-Length header is greater than 0
--- config
    location = /t {

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("body: '", sdk.request:get_body(), "'")
        }
    }
--- request
POST /t
not ignored
--- more_headers
Content-Length: 11
--- response_body
body: 'not ignored'
--- no_error_log
[error]



=== TEST 4: request.get_body() returns the passed body for short bodies
--- config
    location = /t {

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("body: '", sdk.request:get_body(), "'")
        }
    }
--- request
GET /t
potato
--- response_body
body: 'potato'
--- no_error_log
[error]



=== TEST 5: request.get_body() returns nil + error when the body is just too big
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local body, err = sdk.request:get_body()
            if body then
              ngx.say("body: ", body)
            else
              ngx.say("body err: ", err)
            end
        }
    }
--- request eval
"GET /t\r\n" . ("a" x 20000)
--- response_body
body err: request body did not fit into client body buffer, consider raising 'client_body_buffer_size'
--- no_error_log
[error]
