use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_method() returns request method as string 1/2
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("method: ", pdk.request.get_method())
        }
    }
--- request
GET /t
--- response_body
method: GET
--- no_error_log
[error]



=== TEST 2: request.get_method() returns request method as string 2/2
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("method: ", pdk.request.get_method())
        }
    }
--- request
POST /t
--- response_body
method: POST
--- no_error_log
[error]
