use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_http_version() returns request http version 1.0
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("version: ", pdk.request.get_http_version())
        }
    }
--- request
GET /t HTTP/1.0
--- response_body
version: 1
--- no_error_log
[error]



=== TEST 2: request.get_http_version() returns request http version 1.1
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("version: ", pdk.request.get_http_version())
        }
    }
--- request
GET /t
--- response_body
version: 1.1
--- no_error_log
[error]



=== TEST 3: request.get_http_version() returns a number
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("type: ", type(pdk.request.get_http_version()))
        }
    }
--- request
GET /t
--- response_body
type: number
--- no_error_log
[error]
