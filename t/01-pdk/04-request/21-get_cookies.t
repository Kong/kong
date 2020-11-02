use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_cookies() returns a table
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("type: ", type(pdk.request.get_cookies()))
        }
    }
--- request
GET /t
--- more_headers
Cookie: X-Cookie-Foo=Hello; X-Cookie-Bar=World
--- response_body
type: table
--- no_error_log
[error]


=== TEST 2: request.get_cookies() returns request cookies
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local cookies = pdk.request.get_cookies()
            for k, v in pairs(cookies) do
                ngx.say(k, " => ", v)
            end
        }
    }
--- request
GET /t
--- more_headers
Cookie: X-Cookie-Foo=Hello; X-Cookie-Bar=World
--- response_body
X-Cookie-Foo => Hello
X-Cookie-Bar => World
--- no_error_log
[error]


=== TEST 3: request.get_cookies() returns nil when cookie header not exist
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local cookies = pdk.request.get_cookies()
            if not cookies then
                ngx.say(cookies)
                return
            end
        }
    }
--- request
GET /t
--- more_headers
--- response_body
nil
--- no_error_log
[error]
