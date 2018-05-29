use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_raw_body() returns empty strings for empty bodies
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("body: '", sdk.request.get_raw_body(), "'")
        }
    }
--- request
GET /t
--- response_body
body: ''
--- no_error_log
[error]



=== TEST 2: request.get_raw_body() returns empty string when Content-Length header is less than 1
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("body: '", sdk.request.get_raw_body(), "'")
        }
    }
--- request
POST /t
ignored
--- more_headers
Content-Length: 0
--- response_body
body: ''
--- no_error_log
[error]



=== TEST 3: request.get_raw_body() returns body string when Content-Length header is greater than 0
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("body: '", sdk.request.get_raw_body(), "'")
        }
    }
--- request
POST /t
not ignored
--- more_headers
Content-Length: 11
--- response_body
body: 'not ignored'
--- no_error_log
[error]



=== TEST 4: request.get_raw_body() returns the passed body for short bodies
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("body: '", sdk.request.get_raw_body(), "'")
        }
    }
--- request
GET /t
potato
--- response_body
body: 'potato'
--- no_error_log
[error]



=== TEST 5: request.get_raw_body() returns nil + error when the body is too big
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local body, err = sdk.request.get_raw_body()
            if body then
              ngx.say("body: ", body)

            else
              ngx.say("body err: ", err)
            end
        }
    }
--- request eval
"GET /t\r\n" . ("a" x 20000)
--- response_body
body err: request body did not fit into client body buffer, consider raising 'client_body_buffer_size'
--- no_error_log
[error]



=== TEST 6: request.get_raw_body() errors on non-supported phases
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

                local ok, err = pcall(sdk.request.get_raw_body)
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
kong.request.get_raw_body is disabled in the context of set
kong.request.get_raw_body is disabled in the context of content
kong.request.get_raw_body is disabled in the context of log
kong.request.get_raw_body is disabled in the context of header_filter
kong.request.get_raw_body is disabled in the context of body_filter
kong.request.get_raw_body is disabled in the context of timer
kong.request.get_raw_body is disabled in the context of init_worker
kong.request.get_raw_body is disabled in the context of balancer
kong.request.get_raw_body is disabled in the context of ssl_cert
kong.request.get_raw_body is disabled in the context of ssl_session_store
kong.request.get_raw_body is disabled in the context of ssl_session_fetch
--- no_error_log
[error]
