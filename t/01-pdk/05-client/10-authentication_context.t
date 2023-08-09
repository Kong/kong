use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
do "./t/Util.pm";

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: client.set_authentication_context() and client.get_authentication_context()
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            _G.kong = {
              ctx = {
                core = {
                },
              },
            }

            ngx.ctx.KONG_PHASE = 0x00000020

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.client.set_authentication_context({ username = "foo" })
            local authentication_context = pdk.client.get_authentication_context()
            ngx.say("username: " .. authentication_context.username)
        }
    }
--- request
GET /t
--- response_body
username: foo
--- no_error_log
[error]
