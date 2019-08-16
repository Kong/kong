use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: client.get_authenticated_groups() returns groups
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            ngx.ctx.authenticated_groups = {
              [1] = "users",
              [2] = "admins",
              users = "users",
              admins = "admins",
            }

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(200, { groups = pdk.client.get_authenticated_groups() })
        }
    }
--- request
GET /t
--- response_body chop
{"groups":{"1":"users","2":"admins","admins":"admins","users":"users"}}
--- no_error_log
[error]
