use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: router.get_route() returns selected route
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            ngx.ctx.route = setmetatable({},{
                __tostring = function() return "this route" end,
            })

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("route: ", tostring(pdk.router.get_route()))
        }
    }
--- request
GET /t
--- response_body
route: this route
--- no_error_log
[error]



=== TEST 2: router.get_route() returns nil if not set
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            ngx.ctx.route = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("route: ", tostring(pdk.router.get_route()))
        }
    }
--- request
GET /t
--- response_body
route: nil
--- no_error_log
[error]
