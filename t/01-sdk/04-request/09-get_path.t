use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_path() returns path component of uri
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("path: ", sdk.request.get_path())
        }
    }
--- request
GET /t
--- response_body
path: /t
--- no_error_log
[error]



=== TEST 2: request.get_path() returns at least slash
--- config
    location = / {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("path: ", sdk.request.get_path())
        }
    }
--- request
GET http://kong
--- response_body
path: /
--- no_error_log
[error]



=== TEST 3: request.get_path() is not normalized
--- config
    location /t/ {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("path: ", sdk.request.get_path())
        }
    }
--- request
GET /t/Abc%20123%C3%B8/../test/.
--- response_body
path: /t/Abc%20123%C3%B8/../test/.
--- no_error_log
[error]



=== TEST 4: request.get_path() strips query string
--- config
    location /t/ {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("path: ", sdk.request.get_path())
        }
    }
--- request
GET /t/demo?param=value
--- response_body
path: /t/demo
--- no_error_log
[error]



=== TEST 5: request.get_path() errors on non-supported phases
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

                local ok, err = pcall(sdk.request.get_path)
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
kong.request.get_path is disabled in the context of set
kong.request.get_path is disabled in the context of content
kong.request.get_path is disabled in the context of timer
kong.request.get_path is disabled in the context of init_worker
kong.request.get_path is disabled in the context of balancer
kong.request.get_path is disabled in the context of ssl_cert
kong.request.get_path is disabled in the context of ssl_session_store
kong.request.get_path is disabled in the context of ssl_session_fetch
--- no_error_log
[error]
