use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

no_long_string();

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: ctx.shared namespace exists
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.ctx.shared.hello = "world"
            pdk.ctx.shared.cats = {
              "marry",
              "suzie"
            }

            ngx.say(pdk.ctx.shared.hello)
            ngx.say(pdk.ctx.shared.cats[1])
            ngx.say(ngx.ctx.shared)
            ngx.say(ngx.ctx.hello)
        }
    }
--- request
GET /t
--- response_body
world
marry
nil
nil
--- no_error_log
[error]



=== TEST 2: ctx.shared namespace is shared between PDK instances
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk1 = PDK.new()
            local pdk2 = PDK.new()

            pdk1.ctx.shared.hello = "world"

            ngx.say(pdk2.ctx.shared.hello)
        }
    }
--- request
GET /t
--- response_body
world
--- no_error_log
[error]
