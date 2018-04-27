use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

no_long_string();

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: init_sdk() attaches SDK to given global
--- config
    location = /t {
        content_by_lua_block {
            local kong_global = require "kong.global"
            local kong = kong_global.new()

            ngx.say(kong.sdk_major_version)

            kong_global.init_sdk(kong)

            ngx.say(kong.sdk_major_version)
        }
    }
--- request
GET /t
--- response_body
nil
1
--- no_error_log
[error]



=== TEST 2: init_sdk() arg #1 validation
--- config
    location = /t {
        content_by_lua_block {
            local kong_global = require "kong.global"
            local kong = kong_global.new()

            local pok, perr = pcall(kong_global.init_sdk)
            if not pok then
                ngx.say(perr)
            end
        }
    }
--- request
GET /t
--- response_body
arg #1 cannot be nil
--- no_error_log
[error]
