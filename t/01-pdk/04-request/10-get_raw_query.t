use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_raw_query() returns query component of uri
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("query: ", pdk.request.get_raw_query())
        }
    }
--- request
GET /t?query
--- response_body
query: query
--- no_error_log
[error]



=== TEST 2: request.get_raw_query() returns empty string on missing query string
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("query: '", pdk.request.get_raw_query(), "'")
        }
    }
--- request
GET /t
--- response_body
query: ''
--- no_error_log
[error]



=== TEST 3: request.get_raw_query() returns empty string with empty query string
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("query: '", pdk.request.get_raw_query(), "'")
        }
    }
--- request
GET /t?
--- response_body
query: ''
--- no_error_log
[error]



=== TEST 4: request.get_raw_query() is not normalized
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("query: ", pdk.request.get_raw_query())
        }
    }
--- request
GET /t?Abc%20123%C3%B8/../test/.
--- response_body
query: Abc%20123%C3%B8/../test/.
--- no_error_log
[error]
