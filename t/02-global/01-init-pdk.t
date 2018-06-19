use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

no_long_string();

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: init_pdk() attaches PDK to given global
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local kong_global = require "kong.global"
            local kong = kong_global.new()

            ngx.say(kong.pdk_major_version)

            kong_global.init_pdk(kong)

            ngx.say(kong.pdk_major_version)
        }
    }
--- request
GET /t
--- response_body
nil
1
--- no_error_log
[error]



=== TEST 2: init_pdk() arg #1 validation
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local kong_global = require "kong.global"
            local kong = kong_global.new()

            local pok, perr = pcall(kong_global.init_pdk)
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
