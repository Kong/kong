use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: table.new()
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.table.new(0, 12)

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]



=== TEST 2: table.clear()
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local t = {
                hello = "world",
                "foo",
                "bar"
            }

            pdk.table.clear(t)

            ngx.say("hello: ", nil)
            ngx.say("#t: ", #t)
        }
    }
--- request
GET /t
--- response_body
hello: nil
#t: 0
--- no_error_log
[error]
