use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_header() returns first header when multiple is given with same name
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("accept header value: ", sdk.request.get_header("Accept"))
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
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("X-Foo-Header: ", sdk.request.get_header("X-Foo-Header"))
            ngx.say("x-Foo-header: ", sdk.request.get_header("x-Foo-header"))
            ngx.say("x_foo_header: ", sdk.request.get_header("x_foo_header"))
            ngx.say("x_Foo_header: ", sdk.request.get_header("x_Foo_header"))
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
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("X-Missing: ", sdk.request.get_header("X-Missing"))
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
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("X-Foo-Header: '", sdk.request.get_header("X-Foo-Header"), "'")
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
--- config
    location = /t {
        rewrite_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            for name in pairs(sdk.request.get_headers()) do
                ngx.req.clear_header(name)
            end

            for i = 1, 100 do
                ngx.req.set_header("X-Header-" .. i, "test")
            end

            ngx.req.set_header("Accept", "text/html")
        }

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("accept header value: ", sdk.request.get_header("Accept"))
        }
    }
--- request
GET /t
--- response_body
accept header value: nil
--- no_error_log
[error]



=== TEST 6: request.get_header() raises error when trying to fetch with invalid argument
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local _, err = pcall(sdk.request.get_header)

            ngx.say("error: ", err)
        }
    }
--- request
GET /t
--- response_body
error: header name must be a string
--- no_error_log
[error]



=== TEST 7: request.get_header() errors on non-supported phases
--- http_config
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local phases = {
                "set",
                "rewrite",
                "access",
                "content",
                "log",
                "header_filter",
                "body_filter",
                "timer",
                "init_worker",
                "balancer",
                "ssl_cert",
                "ssl_session_store",
                "ssl_session_fetch",
            }

            local data = {}
            local i = 0

            for _, phase in ipairs(phases) do
                ngx.get_phase = function()
                    return phase
                end

                local ok, err = pcall(sdk.request.get_header, "Test")
                if not ok then
                    i = i + 1
                    data[i] = err
                end
            end

            ngx.say(table.concat(data, "\n"))
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body
kong.request.get_header is disabled in the context of set
kong.request.get_header is disabled in the context of content
kong.request.get_header is disabled in the context of timer
kong.request.get_header is disabled in the context of init_worker
kong.request.get_header is disabled in the context of balancer
kong.request.get_header is disabled in the context of ssl_cert
kong.request.get_header is disabled in the context of ssl_session_store
kong.request.get_header is disabled in the context of ssl_session_fetch
--- no_error_log
[error]
