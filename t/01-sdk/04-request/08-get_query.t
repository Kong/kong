use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_query() returns query component of uri
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("query: ", sdk.request.get_query())
        }
    }
--- request
GET /t?query
--- response_body
query: query
--- no_error_log
[error]



=== TEST 2: request.get_query() returns empty string on missing query string
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("query: '", sdk.request.get_query(), "'")
        }
    }
--- request
GET /t
--- response_body
query: ''
--- no_error_log
[error]



=== TEST 3: request.get_query() returns empty string with empty query string
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("query: '", sdk.request.get_query(), "'")
        }
    }
--- request
GET /t?
--- response_body
query: ''
--- no_error_log
[error]



=== TEST 4: request.get_query() is not normalized
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("query: ", sdk.request.get_query())
        }
    }
--- request
GET /t?Abc%20123%C3%B8/../test/.
--- response_body
query: Abc%20123%C3%B8/../test/.
--- no_error_log
[error]
