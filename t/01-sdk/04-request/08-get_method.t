use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_method() returns request method as string 1/2
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("method: ", sdk.request.get_method())
        }
    }
--- request
GET /t
--- response_body
method: GET
--- no_error_log
[error]



=== TEST 2: request.get_method() returns request method as string 2/2
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("method: ", sdk.request.get_method())
        }
    }
--- request
POST /t
--- response_body
method: POST
--- no_error_log
[error]



=== TEST 3: request.get_method() errors on non-supported phases
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

                local ok, err = pcall(sdk.request.get_method)
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
kong.request.get_method is disabled in the context of set
kong.request.get_method is disabled in the context of content
kong.request.get_method is disabled in the context of timer
kong.request.get_method is disabled in the context of init_worker
kong.request.get_method is disabled in the context of balancer
kong.request.get_method is disabled in the context of ssl_cert
kong.request.get_method is disabled in the context of ssl_session_store
kong.request.get_method is disabled in the context of ssl_session_fetch
--- no_error_log
[error]
