use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

plan tests => repeat_each() * (blocks() * 4);

run_tests();

__DATA__

=== TEST 1: response.exit() code must be a number
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = pcall(sdk.response.exit)
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body
code must be a number
--- no_error_log
[error]



=== TEST 2: response.exit() code must be a number between 100 and 599
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok1, err1 = pcall(sdk.response.exit, 99)
            local ok2, err2 = pcall(sdk.response.exit, 600)

            if not ok1 then
                ngx.say(err1)
            end

            if not ok2 then
                ngx.print(err2)
            end
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body chop
code must be a number between 100 and 599
code must be a number between 100 and 599
--- no_error_log
[error]



=== TEST 3: response.exit() body must be a nil, string or table
--- config
    location = /t {
        access_by_lua_block {
            local ffi = require "ffi"
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok1, err1 = pcall(sdk.response.exit, 200, pcall)
            local ok2, err2 = pcall(sdk.response.exit, 200, ngx.null)
            local ok3, err3 = pcall(sdk.response.exit, 200, true)
            local ok4, err4 = pcall(sdk.response.exit, 200, false)
            local ok5, err5 = pcall(sdk.response.exit, 200, 0)
            local ok6, err6 = pcall(sdk.response.exit, 200, coroutine.create(function() end))
            local ok7, err7 = pcall(sdk.response.exit, 200, ffi.new("int[?]", 1))

            if not ok1 then ngx.say(err1)   end
            if not ok2 then ngx.say(err2)   end
            if not ok3 then ngx.say(err3)   end
            if not ok4 then ngx.say(err4)   end
            if not ok5 then ngx.say(err5)   end
            if not ok6 then ngx.say(err6)   end
            if not ok7 then ngx.print(err7) end
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body chop
body must be a nil, string or table
body must be a nil, string or table
body must be a nil, string or table
body must be a nil, string or table
body must be a nil, string or table
body must be a nil, string or table
body must be a nil, string or table
--- no_error_log
[error]



=== TEST 4: response.exit() errors if headers have already been sent
--- config
    location = /t {
        access_by_lua_block {
            ngx.send_headers()

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = pcall(sdk.response.exit, 200)
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body
headers have been sent
--- no_error_log
[error]



=== TEST 5: response.exit() errors if headers have already been sent with delayed response
--- config
    location = /t {
        access_by_lua_block {
            ngx.ctx.delay_response = true

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(500, "ok")
        }
        content_by_lua_block {
            ngx.send_headers()

            local ok, err = pcall(ngx.ctx.delayed_response_callback, ngx.ctx)
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body
headers have been sent
--- no_error_log
[error]



=== TEST 6: response.exit() skips all the content phases
--- config
    location = /t {
        rewrite_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(200)
            ngx.ctx.rewite = true
        }

        access_by_lua_block {
            ngx.ctx.access = true
        }

        content_by_lua_block {
            ngx.ctx.content = true
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil
            ngx.ctx.header_filter = true
        }

        body_filter_by_lua_block {
            ngx.arg[1] = tostring(ngx.ctx.rewrite) .. "\n" ..
                         tostring(ngx.ctx.access)  .. "\n" ..
                         tostring(ngx.ctx.content) .. "\n" ..
                         tostring(ngx.ctx.header_filter)
            ngx.arg[2] = true
        }

    }
--- request
GET /t
--- error_code: 200
--- response_body chop
nil
nil
nil
true
--- no_error_log
[error]



=== TEST 7: response.exit() has no default content
--- config
    location = /t {
        default_type '';
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(456)
        }
    }
--- request
GET /t
--- error_code: 456
--- response_body chop

--- no_error_log
[error]



=== TEST 8: response.exit() has no default content (delayed)
--- config
    location = /t {
        default_type '';
        access_by_lua_block {
            ngx.ctx.delay_response = true

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(456)
        }
        content_by_lua_block {
            ngx.ctx:delayed_response_callback()
        }
    }
--- request
GET /t
--- error_code: 456
--- response_headers_like
Server: kong/\d+\.\d+\.\d+
--- response_body chop

--- no_error_log
[error]



=== TEST 9: response.exit() adds server header
--- config
    location = /t {
        default_type '';
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(ngx.HTTP_NO_CONTENT)
        }
    }
--- request
GET /t
--- error_code: 204
--- response_headers_like
Server: kong/\d+\.\d+\.\d+
--- response_body chop

--- no_error_log
[error]



=== TEST 10: response.exit() errors if headers is not a table
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.response.exit, 200, nil, 127001)
            ngx.say(err)
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body
headers must be a nil or table
--- no_error_log
[error]



=== TEST 11: response.exit() errors if header name is not a string
--- http_config
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.response.exit, 200, nil, {[2] = "foo"})
            assert(not pok)
            ngx.say(err)
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body
invalid header name "2": got number, expected string
--- no_error_log
[error]



=== TEST 12: response.exit() errors if header value is of a bad type
--- http_config
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.response.exit, 200, nil, {["foo"] = 2})
            assert(not pok)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
invalid header value in "foo": got number, expected string
--- no_error_log
[error]



=== TEST 13: response.exit() errors if header value array element is of a bad type
--- http_config
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.response.exit, 200, nil, {["foo"] = {2}})
            assert(not pok)
            ngx.say(err)
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body
invalid header value in array "foo": got number, expected string
--- no_error_log
[error]



=== TEST 14: response.exit() sends "text/plain" response
--- http_config
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(200, "hello", { ["Content-Type"] = "text/plain" })
        }
    }
--- request
GET /t
--- error_code: 200
--- response_headers_like
Server: kong/\d+\.\d+\.\d+
Content-Type: text/plain
--- response_body chop
hello
--- no_error_log
[error]



=== TEST 15: response.exit() sends no content-type header by default
--- http_config
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(200, "hello")
        }
    }
--- request
GET /t
--- error_code: 200
--- response_headers_like
Server: kong/\d+\.\d+\.\d+
Content-Type: text/test
--- response_body chop
hello
--- no_error_log
[error]



=== TEST 16: response.exit() sends json response when body is table
--- http_config
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(200, { message = "hello" })
        }
    }
--- request
GET /t
--- error_code: 200
--- response_headers_like
Server: kong/\d+\.\d+\.\d+
Content-Type: application/json; charset=utf-8
--- response_body chop
{"message":"hello"}
--- no_error_log
[error]



=== TEST 17: response.exit() sends json response when body is table overrides content-type
--- http_config
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(200, { message = "hello" }, {
                ["Content-Type"] = "text/plain"
            })
        }
    }
--- request
GET /t
--- error_code: 200
--- response_headers_like
Server: kong/\d+\.\d+\.\d+
Content-Type: application/json; charset=utf-8
--- response_body chop
{"message":"hello"}
--- no_error_log
[error]



=== TEST 18: response.exit() sets content-length header
--- http_config
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(200, "", {
                ["Content-Type"] = "text/plain"
            })
        }
    }
--- request
GET /t
--- error_code: 200
--- response_headers_like
Server: kong/\d+\.\d+\.\d+
Content-Type: text/plain
Content-Length: 0
--- response_body chop

--- no_error_log
[error]



=== TEST 19: response.exit() sets content-length header even when no body
--- http_config
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(200, nil, {
                ["Content-Type"] = "text/plain",
                ["Content-Length"] = "100"
            })
        }
    }
--- request
GET /t
--- error_code: 200
--- response_headers_like
Server: kong/\d+\.\d+\.\d+
Content-Type: text/plain
Content-Length: 0
--- response_body chop

--- no_error_log
[error]



=== TEST 20: response.exit() sets content-length header with text body
--- http_config
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(200, "a", {
                ["Content-Type"] = "text/plain",
                ["Content-Length"] = "100"
            })
        }
    }
--- request
GET /t
--- error_code: 200
--- response_headers_like
Server: kong/\d+\.\d+\.\d+
Content-Type: text/plain
Content-Length: 1
--- response_body chop
a
--- no_error_log
[error]



=== TEST 21: response.exit() sets content-length header with table body
--- http_config
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(200, { message = "hello" }, {
                ["Content-Type"] = "text/plain",
                ["Content-Length"] = "100"
            })
        }
    }
--- request
GET /t
--- error_code: 200
--- response_headers_like
Server: kong/\d+\.\d+\.\d+
Content-Type: application/json; charset=utf-8
Content-Length: 19
--- response_body chop
{"message":"hello"}
--- no_error_log
[error]



=== TEST 22: response.exit() errors on non-supported phases
--- http_config
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local unsupported_phases = {
                "set",
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

            for _, phase in ipairs(unsupported_phases) do
                ngx.get_phase = function()
                    return phase
                end

                local ok, err = pcall(sdk.response.exit, 500)
                if not ok then
                    ngx.say(err)
                end
            end
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body
kong.response.exit is disabled in the context of set
kong.response.exit is disabled in the context of content
kong.response.exit is disabled in the context of log
kong.response.exit is disabled in the context of header_filter
kong.response.exit is disabled in the context of body_filter
kong.response.exit is disabled in the context of timer
kong.response.exit is disabled in the context of init_worker
kong.response.exit is disabled in the context of balancer
kong.response.exit is disabled in the context of ssl_cert
kong.response.exit is disabled in the context of ssl_session_store
kong.response.exit is disabled in the context of ssl_session_fetch
--- no_error_log
[error]
