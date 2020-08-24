use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_cookie() returns cookie value using cookie header
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
 
            ngx.say("Cookie value: ", pdk.request.get_cookie("X-Cookie-Foo"))
        }
    }
--- request
GET /t
--- more_headers
Cookie: X-Cookie-Foo=Hello; X-Cookie-Bar=World
--- response_body
Cookie value: Hello
--- no_error_log
[error]


=== TEST 2: request.get_cookie() returns nil with case-sensitive
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
 
            local cookie, err = pdk.request.get_cookie("X-Cookie-foo")
            if not cookie then
                ngx.say(err)
                return
            end
        }
    }
--- request
GET /t
--- more_headers
Cookie: X-Cookie-Foo=Hello; X-Cookie-Bar=World
--- response_body
nil
--- no_error_log
[error]


=== TEST 3: request.get_cookie() returns nil when cookie name is missing
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
 
            local cookie, err = pdk.request.get_cookie("X-Cookie-Missing")
            if not cookie then
                ngx.say(err)
                return
            end
        }
    }
--- request
GET /t
--- more_headers
Cookie: X-Cookie-Foo=Hello; X-Cookie-Bar=World
--- response_body
nil
--- no_error_log
[error]


=== TEST 4: request.get_cookie() returns nil when cookie header not exist
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
 
            local cookie, err = pdk.request.get_cookie("X-Cookie-Foo")
            if not cookie then
                ngx.say(err)
                return
            end
        }
    }
--- request
GET /t
--- more_headers
--- response_body
no cookie found in the current request
--- no_error_log
[error]
