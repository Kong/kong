use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_header() returns first header when multiple is given with same name
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("accept header value: ", pdk.request.get_header("Accept"))
        }
    }
--- request
GET /t
--- more_headers
Accept: application/json
Accept: text/html
--- response_body
accept header value: application/json
--- no_error_log
[error]



=== TEST 2: request.get_header() returns values from case-insensitive metatable
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("X-Foo-Header: ", pdk.request.get_header("X-Foo-Header"))
            ngx.say("x-Foo-header: ", pdk.request.get_header("x-Foo-header"))
            ngx.say("x_foo_header: ", pdk.request.get_header("x_foo_header"))
            ngx.say("x_Foo_header: ", pdk.request.get_header("x_Foo_header"))
        }
    }
--- request
GET /t
--- more_headers
X-Foo-Header: Hello
--- response_body
X-Foo-Header: Hello
x-Foo-header: Hello
x_foo_header: Hello
x_Foo_header: Hello
--- no_error_log
[error]



=== TEST 3: request.get_header() returns nil when header is missing
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("X-Missing: ", pdk.request.get_header("X-Missing"))
        }
    }
--- request
GET /t
--- more_headers
X-Foo-Header: Hello
--- response_body
X-Missing: nil
--- no_error_log
[error]



=== TEST 4: request.get_header() returns empty string when header has no value
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("X-Foo-Header: '", pdk.request.get_header("X-Foo-Header"), "'")
        }
    }
--- request
GET /t
--- more_headers
X-Foo-Header:
--- response_body
X-Foo-Header: ''
--- no_error_log
[error]



=== TEST 5: request.get_header() returns nil when requested header does not fit in default max_headers
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        rewrite_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            for name in pairs(pdk.request.get_headers()) do
                ngx.req.clear_header(name)
            end

            for i = 1, 100 do
                ngx.req.set_header("X-Header-" .. i, "test")
            end

            ngx.req.set_header("Accept", "text/html")
        }

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("accept header value: ", pdk.request.get_header("Accept"))
        }
    }
--- request
GET /t
--- response_body
accept header value: nil
--- no_error_log
[error]



=== TEST 6: request.get_header() raises error when trying to fetch with invalid argument
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local _, err = pcall(pdk.request.get_header)

            ngx.say("error: ", err)
        }
    }
--- request
GET /t
--- response_body
error: header name must be a string
--- no_error_log
[error]
