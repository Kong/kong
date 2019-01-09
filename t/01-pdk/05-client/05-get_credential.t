use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: client.get_credential() returns selected credential
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            ngx.ctx.authenticated_credential = setmetatable({},{
                __tostring = function() return "this credential" end,
            })

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("credential: ", tostring(pdk.client.get_credential()))
        }
    }
--- request
GET /t
--- response_body
credential: this credential
--- no_error_log
[error]



=== TEST 2: client.get_service() returns nil if not set
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            ngx.ctx.authenticated_credential = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("credential: ", tostring(pdk.client.get_credential()))
        }
    }
--- request
GET /t
--- response_body
credential: nil
--- no_error_log
[error]
