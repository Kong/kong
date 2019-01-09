use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: client.get_consumer() returns selected consumer
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            ngx.ctx.authenticated_consumer = setmetatable({},{
                __tostring = function() return "this consumer" end,
            })

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("consumer: ", tostring(pdk.client.get_consumer()))
        }
    }
--- request
GET /t
--- response_body
consumer: this consumer
--- no_error_log
[error]



=== TEST 2: client.get_service() returns nil if not set
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            ngx.ctx.authenticated_consumer = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("consumer: ", tostring(pdk.client.get_consumer()))
        }
    }
--- request
GET /t
--- response_body
consumer: nil
--- no_error_log
[error]
