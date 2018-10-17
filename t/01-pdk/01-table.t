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



=== TEST 3: table.merge()
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local inspect = require "inspect"
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            local function insp(x)
                return inspect(x, { newline = "", indent = "" })
            end

            ngx.say(insp(pdk.table.merge({ x = "hello" }, { y = "world" })))
            ngx.say(insp(pdk.table.merge({ x = "hello" }, {})))
            ngx.say(insp(pdk.table.merge({}, { y = "world" })))
            ngx.say(insp(pdk.table.merge({ x = "hello" }, { x = "world" })))
            ngx.say(insp(pdk.table.merge({1, 2, 3, 4, 5}, {6, 7, 8})))
            ngx.say(insp(pdk.table.merge({ x = "hello" }, nil)))
            ngx.say(insp(pdk.table.merge(nil, { y = "world" })))
        }
    }
--- request
GET /t
--- response_body
{x = "hello",y = "world"}
{x = "hello"}
{y = "world"}
{x = "world"}
{ 6, 7, 8, 4, 5 }
{x = "hello"}
{y = "world"}
--- no_error_log
[error]
