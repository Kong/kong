use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: service.request.get_port() returns server port
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            ngx.ctx.balancer_data = {
                port = 8080
            }

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("port: ", pdk.service.request.get_port())
        }
    }
--- request
GET /t
--- response_body_like chomp
port: 8080
--- no_error_log
[error]
