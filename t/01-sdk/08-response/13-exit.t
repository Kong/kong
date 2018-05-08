use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3) + 10;

run_tests();

__DATA__

=== TEST 1: response.exit() code must be a number
--- config
    location = /t {
        content_by_lua_block {
            ngx.send_headers()

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
--- response_body
code must be a number
--- no_error_log
[error]



=== TEST 2: response.exit() code must be a number between 100 and 599
--- config
    location = /t {
        content_by_lua_block {
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
--- response_body chop
code must be a number between 100 and 599
code must be a number between 100 and 599
--- no_error_log
[error]



=== TEST 3: response.exit() body must be a nil, string or table
--- config
    location = /t {
        content_by_lua_block {
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
        content_by_lua_block {
            ngx.send_headers()

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = pcall(sdk.response.exit, 500)
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
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

            sdk.response.exit(500)
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
--- response_body chop
nil
nil
nil
true
--- no_error_log
[error]



=== TEST 7: response.exit(405) has default content
--- config
    location = /t {
        default_type '';
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(ngx.HTTP_NOT_ALLOWED)
        }
    }
--- request
GET /t
--- error_code: 405
--- response_body chop
{"message":"Method Not Allowed"}
--- no_error_log
[error]



=== TEST 8: response.exit(405) has default content (delayed)
--- config
    location = /t {
        default_type '';
        access_by_lua_block {
            ngx.ctx.delay_response = true

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(ngx.HTTP_NOT_ALLOWED)
        }
        content_by_lua_block {
            ngx.ctx:delayed_response_callback()
        }
    }
--- request
GET /t
--- error_code: 405
--- response_body chop
{"message":"Method Not Allowed"}
--- no_error_log
[error]



=== TEST 9: response.exit(401) has default content
--- config
    location = /t {
        default_type '';
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(ngx.HTTP_UNAUTHORIZED)
        }
    }
--- request
GET /t
--- error_code: 401
--- response_body chop
{"message":"Unauthorized"}
--- no_error_log
[error]



=== TEST 10: response.exit(401) has default content (delayed)
--- config
    location = /t {
        default_type '';
        access_by_lua_block {
            ngx.ctx.delay_response = true

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(ngx.HTTP_UNAUTHORIZED)
        }
        content_by_lua_block {
            ngx.ctx:delayed_response_callback()
        }
    }
--- request
GET /t
--- error_code: 401
--- response_body chop
{"message":"Unauthorized"}
--- no_error_log
[error]



=== TEST 11: response.exit(503) has default content
--- config
    location = /t {
        default_type '';
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
        }
    }
--- request
GET /t
--- error_code: 503
--- response_body chop
{"message":"Service Unavailable"}
--- no_error_log
[error]



=== TEST 12: response.exit(503) has default content (delayed)
--- config
    location = /t {
        default_type '';
        access_by_lua_block {
            ngx.ctx.delay_response = true

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
        }
        content_by_lua_block {
            ngx.ctx:delayed_response_callback()
        }
    }
--- request
GET /t
--- error_code: 503
--- response_body chop
{"message":"Service Unavailable"}
--- no_error_log
[error]



=== TEST 13: response.exit(500) has default content
--- config
    location = /t {
        default_type '';
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
        }
    }
--- request
GET /t
--- error_code: 500
--- response_body chop
{"message":"Internal Server Error"}
--- no_error_log
[error]



=== TEST 14: response.exit(500) has default content (delayed)
--- config
    location = /t {
        default_type '';
        access_by_lua_block {
            ngx.ctx.delay_response = true

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
        }
        content_by_lua_block {
            ngx.ctx:delayed_response_callback()
        }
    }
--- request
GET /t
--- error_code: 500
--- response_body chop
{"message":"Internal Server Error"}
--- no_error_log
[error]



=== TEST 15: response.exit(500) has default content and logs the body string
--- config
    location = /t {
        default_type '';
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(ngx.HTTP_INTERNAL_SERVER_ERROR, "error")
        }
    }
--- request
GET /t
--- error_code: 500
--- response_body chop
{"message":"Internal Server Error"}
--- error_log: error



=== TEST 16: response.exit(500) has default content and logs the body table
--- config
    location = /t {
        default_type '';
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(ngx.HTTP_INTERNAL_SERVER_ERROR, { message = "error" })
        }
    }
--- request
GET /t
--- error_code: 500
--- response_body chop
{"message":"Internal Server Error"}
--- error_log: {"message":"error"}



=== TEST 17: response.exit(500) has default content and logs the body table using metamethod
--- config
    location = /t {
        default_type '';
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local body = setmetatable({
                message = "error",
            }, {
                __tostring = function()
                    return "{\"message\":\"failure\"}"
                end,
            })

            sdk.response.exit(
                ngx.HTTP_INTERNAL_SERVER_ERROR,
                body
            )
        }
    }
--- request
GET /t
--- error_code: 500
--- response_body chop
{"message":"Internal Server Error"}
--- error_log: {"message":"failure"}



=== TEST 18: response.exit(456) has no default content
--- config
    location = /t {
        default_type '';
        content_by_lua_block {
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



=== TEST 19: response.exit(456) has no default content (delayed)
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
--- response_body chop
--- no_error_log
[error]



=== TEST 20: response.exit(204) has no content
--- config
    location = /t {
        default_type '';
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(ngx.HTTP_NO_CONTENT)
        }
    }
--- request
GET /t
--- error_code: 204
--- response_body chop
--- no_error_log
[error]



=== TEST 21: response.exit(204) has no content (delayed)
--- config
    location = /t {
        default_type '';
        access_by_lua_block {
            ngx.ctx.delay_response = true

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(ngx.HTTP_NO_CONTENT)
        }
        content_by_lua_block {
            ngx.ctx:delayed_response_callback()
        }
    }
--- request
GET /t
--- error_code: 204
--- response_body chop
--- no_error_log
[error]



=== TEST 22: response.exit(204) has no content even when body is given
--- config
    location = /t {
        default_type '';
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(ngx.HTTP_NO_CONTENT, "no content")
        }
    }
--- request
GET /t
--- error_code: 204
--- response_body chop
--- no_error_log
[error]



=== TEST 23: response.exit() adds server header
--- config
    location = /t {
        default_type '';
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(ngx.HTTP_NO_CONTENT, "no content")
        }
    }
--- request
GET /t
--- error_code: 204
--- response_headers_like
Server: kong/\d+\.\d+\.\d+
--- no_error_log
[error]



=== TEST 24: response.exit() errors if headers is not a table
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.response.exit, 200, nil, 127001)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
headers must be a nil or table
--- no_error_log
[error]



=== TEST 25: response.exit() errors if header name is not a string
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
--- response_body
invalid header name "2": got number, expected string
--- no_error_log
[error]



=== TEST 26: response.exit() errors if header value is of a bad type
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



=== TEST 27: response.exit() errors if header value array element is of a bad type
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
--- response_body
invalid header value in array "foo": got number, expected string
--- no_error_log
[error]



=== TEST 28: response.exit() sends "text/plain" response
--- http_config
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(200, "hello", { ["Content-Type"] = "text/plain" })
        }
    }
--- request
GET /t
--- response_headers_like
Server: kong/\d+\.\d+\.\d+
Content-Type: text/plain
--- response_body chop
hello
--- no_error_log
[error]



=== TEST 29: response.exit() sends "application/json; charset=utf-8" response by default
--- http_config
--- config
    location = /t {
        default_type '';
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(200, "hello")
        }
    }
--- request
GET /t
--- response_headers_like
Server: kong/\d+\.\d+\.\d+
Content-Type: application/json; charset=utf-8
--- response_body chop
{"message":"hello"}
--- no_error_log
[error]



=== TEST 30: response.exit() sends "application/json" response when asked
--- http_config
--- config
    location = /t {
        default_type '';
        access_by_lua_block {
            ngx.header["Content-Type"] = "application/json"
        }
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(200, { message = "hello" })
        }
    }
--- request
GET /t
--- response_headers_like
Server: kong/\d+\.\d+\.\d+
Content-Type: application/json
--- response_body chop
{"message":"hello"}
--- no_error_log
[error]



=== TEST 31: response.exit() sends "text/xml" response as empty when using table
--- http_config
--- config
    location = /t {
        default_type 'text/xml';
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.exit(200, { message = "hello" })
        }
    }
--- request
GET /t
--- response_headers_like
Server: kong/\d+\.\d+\.\d+
Content-Type: text/xml
--- response_body
--- no_error_log
[error]



=== TEST 32: response.exit() sends "text/plain" response as empty when using table with metamethod
--- http_config
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local response = setmetatable(
                {
                    message = "hello"
                }, {
                    __tostring = function(self)
                        return self.message .. " " .. "world"
                    end
                }
            )

            sdk.response.exit(200, response, { ["Content-Type"] = "text/plain" })
        }
    }
--- request
GET /t
--- response_headers_like
Server: kong/\d+\.\d+\.\d+
Content-Type: text/plain
--- response_body chop
hello world
--- no_error_log
[error]
