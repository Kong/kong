use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 2);

run_tests();

__DATA__

=== TEST 1: request.get_start_time() returns a number
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require("kong.pdk")
            local pdk = PDK.new()

            ngx.say("request start time: ", string.format("%.3f", pdk.request.get_start_time()))
        }
    }
--- request
GET /t
request start time: \d+\.?\d\d\d
--- no_error_log
[error]

