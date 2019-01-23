use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: router.get_service() returns selected service
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            ngx.ctx.service = setmetatable({},{
                __tostring = function() return "this service" end,
            })

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("service: ", tostring(pdk.router.get_service()))
        }
    }
--- request
GET /t
--- response_body
service: this service
--- no_error_log
[error]



=== TEST 2: router.get_service() returns nil if not set
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            ngx.ctx.service = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("service: ", tostring(pdk.router.get_service()))
        }
    }
--- request
GET /t
--- response_body
service: nil
--- no_error_log
[error]
