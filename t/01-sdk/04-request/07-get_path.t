use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_path() returns path component of uri
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("path: ", sdk.request.get_path())
        }
    }
--- request
GET /t
--- response_body
path: /t
--- no_error_log
[error]



=== TEST 2: request.get_path() returns at least slash
--- config
    location = / {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("path: ", sdk.request.get_path())
        }
    }
--- request
GET http://kong
--- response_body
path: /
--- no_error_log
[error]



=== TEST 3: request.get_path() is not normalized
--- config
    location /t/ {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("path: ", sdk.request.get_path())
        }
    }
--- request
GET /t/Abc%20123%C3%B8/../test/.
--- response_body
path: /t/Abc%20123%C3%B8/../test/.
--- no_error_log
[error]



=== TEST 4: request.get_path() strips query string
--- config
    location /t/ {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("path: ", sdk.request.get_path())
        }
    }
--- request
GET /t/demo?param=value
--- response_body
path: /t/demo
--- no_error_log
[error]
