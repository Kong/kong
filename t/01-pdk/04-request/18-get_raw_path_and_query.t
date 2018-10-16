use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_raw_path_and_query() returns the path when no query string is present
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local path_and_querystring = pdk.request.get_raw_path_and_query()

            ngx.say("path_and_querystring=", path_and_querystring)
        }
    }
--- request
GET /t
--- response_body
path_and_querystring=/t
--- no_error_log
[error]

=== TEST 2: request.get_raw_path_and_query() returns the path + ? + querystring when querystring is present
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local path_and_querystring = pdk.request.get_raw_path_and_query()

            ngx.say("path_and_querystring=", path_and_querystring)
        }
    }
--- request
GET /t?foo=1&bar=2
--- response_body
path_and_querystring=/t?foo=1&bar=2
--- no_error_log
[error]
