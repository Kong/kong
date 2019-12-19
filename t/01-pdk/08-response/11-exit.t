use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 4) + 9;

run_tests();

__DATA__

=== TEST 1: response.exit() code must be a number
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local ok, err = pcall(pdk.response.exit)
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
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local ok1, err1 = pcall(pdk.response.exit, 99)
            local ok2, err2 = pcall(pdk.response.exit, 600)

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
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local ffi = require "ffi"
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local ok1, err1 = pcall(pdk.response.exit, 200, pcall)
            local ok2, err2 = pcall(pdk.response.exit, 200, ngx.null)
            local ok3, err3 = pcall(pdk.response.exit, 200, true)
            local ok4, err4 = pcall(pdk.response.exit, 200, false)
            local ok5, err5 = pcall(pdk.response.exit, 200, 0)
            local ok6, err6 = pcall(pdk.response.exit, 200, coroutine.create(function() end))
            local ok7, err7 = pcall(pdk.response.exit, 200, ffi.new("int[?]", 1))

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
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            ngx.send_headers()

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local ok, err = pcall(pdk.response.exit, 200)
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body
headers have already been sent
--- no_error_log
[error]



=== TEST 5: response.exit() errors if headers have already been sent with delayed response
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            ngx.ctx.delay_response = true

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(500, "ok")
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
headers have already been sent
--- no_error_log
[error]



=== TEST 6: response.exit() skips all the content phases
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        rewrite_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(200)
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
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type '';
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(456)
        }
    }
--- request
GET /t
--- error_code: 456
--- response_body chop

--- no_error_log
[error]



=== TEST 8: response.exit() has no default content (delayed)
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type '';
        access_by_lua_block {
            ngx.ctx.delay_response = true

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(456)
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



=== TEST 9: response.exit() adds Server header if in admin_api phase
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type '';
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            local phases = require("kong.pdk.private.phases")
            kong = pdk
            kong.ctx.core.phase = phases.phases.admin_api

            pdk.response.exit(ngx.HTTP_NO_CONTENT)
        }
    }
--- request
GET /t
--- error_code: 204
--- response_headers_like
Server: kong/\d+\.\d+\.\d+(rc\d?)?
--- response_body chop

--- no_error_log
[error]



=== TEST 10: response.exit() does not add Server header if not in admin_api phase
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type '';
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(ngx.HTTP_NO_CONTENT)
        }
    }
--- request
GET /t
--- error_code: 204
--- response_headers_like
Server: openresty/.*
--- response_body chop

--- no_error_log
[error]



=== TEST 11: response.exit() errors if headers is not a table
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.response.exit, 200, nil, 127001)
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



=== TEST 12: response.exit() errors if header name is not a string
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.response.exit, 200, nil, {[2] = "foo"})
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



=== TEST 13: response.exit() errors if header value is of a bad type
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.response.exit, 200, nil, {["foo"] = function() end})
            assert(not pok)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
invalid header value for "foo": got function, expected string, number, boolean or array of strings
--- no_error_log
[error]



=== TEST 14: response.exit() errors if header value array element is of a bad type
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.response.exit, 200, nil, {["foo"] = { function() end }})
            assert(not pok)
            ngx.say(err)
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body
invalid header value in array "foo": got function, expected string
--- no_error_log
[error]



=== TEST 15: response.exit() sends "text/plain" response
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(200, "hello", { ["Content-Type"] = "text/plain" })
        }
    }
--- request
GET /t
--- error_code: 200
--- response_headers_like
Content-Type: text/plain
--- response_body chop
hello
--- no_error_log
[error]



=== TEST 16: response.exit() sends no content-type header by default
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(200, "hello")
        }
    }
--- request
GET /t
--- error_code: 200
--- response_headers_like
Content-Type: text/test
--- response_body chop
hello
--- no_error_log
[error]



=== TEST 17: response.exit() sends json response when body is table
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(200, { message = "hello" })
        }
    }
--- request
GET /t
--- error_code: 200
--- response_headers_like
Content-Type: application/json; charset=utf-8
--- response_body chop
{"message":"hello"}
--- no_error_log
[error]



=== TEST 18: response.exit() sends json response when body is table, but does not override content-type
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(200, { message = "hello" }, {
                ["Content-Type"] = "application/jwk+json; charset=utf-8"
            })
        }
    }
--- request
GET /t
--- error_code: 200
--- response_headers
Content-Type: application/jwk+json; charset=utf-8
--- response_body chop
{"message":"hello"}
--- no_error_log
[error]



=== TEST 19: response.exit() sets content-length header
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(200, "", {
                ["Content-Type"] = "text/plain"
            })
        }
    }
--- request
GET /t
--- error_code: 200
--- response_headers_like
Content-Type: text/plain
Content-Length: 0
--- response_body chop

--- no_error_log
[error]



=== TEST 20: response.exit() sets content-length header even when no body
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(200, nil, {
                ["Content-Type"] = "text/plain",
                ["Content-Length"] = "100"
            })
        }
    }
--- request
GET /t
--- error_code: 200
--- response_headers_like
Content-Type: text/plain
Content-Length: 0
--- response_body chop

--- no_error_log
[error]



=== TEST 21: response.exit() sets content-length header with text body
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(200, "a", {
                ["Content-Type"] = "text/plain",
                ["Content-Length"] = "100"
            })
        }
    }
--- request
GET /t
--- error_code: 200
--- response_headers_like
Content-Type: text/plain
Content-Length: 1
--- response_body chop
a
--- no_error_log
[error]



=== TEST 22: response.exit() sets content-length header with table body
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(200, { message = "hello" }, {
                ["Content-Type"] = "application/jwk+json; charset=utf-8",
                ["Content-Length"] = "100"
            })
        }
    }
--- request
GET /t
--- error_code: 200
--- response_headers
Content-Type: application/jwk+json; charset=utf-8
Content-Length: 19
--- response_body chop
{"message":"hello"}
--- no_error_log
[error]



=== TEST 23: response.exit() does not send body with gRPC
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            ngx.req.http_version = function() return 2 end
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(200, { message = "hello" })
        }
    }
--- request
GET /t
--- more_headers
Content-Type: application/grpc
--- error_code: 200
--- response_headers_like
Content-Length: 0
grpc-status: 0
grpc-message: hello
--- no_error_log
[error]



=== TEST 24: response.exit() sends body with gRPC when asked (explicit)
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(200, "hello", {
                content_type = "application/grpc"
            })
        }
    }
--- request
GET /t
--- error_code: 200
--- response_headers_like
Content-Length: 5
grpc-status: 0
grpc-message: OK
--- response_body chop
hello
--- no_error_log
[error]



=== TEST 25: response.exit() sends body with gRPC when asked (implicit)
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.set_header("Content-Type", "application/grpc")
            pdk.response.exit(200, "hello")
        }
    }
--- request
GET /t
--- error_code: 200
--- response_headers_like
Content-Length: 5
grpc-status: 0
grpc-message: OK
--- response_body chop
hello
--- no_error_log
[error]



=== TEST 26: response.exit() body replaces grpc-message
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            ngx.req.http_version = function() return 2 end

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(200, "OK", {
              ["grpc-message"] = "REPLACE ME"
            })
        }
    }
--- request
GET /t
--- more_headers
Content-Type: application/grpc
--- error_code: 200
--- response_headers_like
Content-Length: 0
grpc-status: 0
grpc-message: OK
--- response_body chop
--- no_error_log
[error]



=== TEST 27: response.exit() body does not replace grpc-message with content-type specified (explicit)
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(200, "OK", {
              ["Content-Type"]  = "application/grpc",
              ["grpc-message"] = "SHOW ME"
            })
        }
    }
--- request
GET /t
--- error_code: 200
--- response_headers_like
Content-Length: 2
grpc-status: 0
grpc-message: SHOW ME
--- response_body chop
OK
--- no_error_log
[error]



=== TEST 28: response.exit() body does not replace grpc-message with content-type specified (implicit)
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.set_header("Content-Type", "application/grpc")
            pdk.response.exit(200, "OK", {
              ["grpc-message"] = "SHOW ME"
            })
        }
    }
--- request
GET /t
--- error_code: 200
--- response_headers_like
Content-Length: 2
grpc-status: 0
grpc-message: SHOW ME
--- response_body chop
OK
--- no_error_log
[error]



=== TEST 29: response.exit() nil body does not replace grpc-message with default message
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.set_header("Content-Type", "application/grpc")
            pdk.response.exit(200, nil, {
              ["grpc-message"] = "SHOW ME"
            })
        }
    }
--- request
GET /t
--- error_code: 200
--- response_headers_like
Content-Length: 0
grpc-status: 0
grpc-message: SHOW ME
--- response_body chop
--- no_error_log
[error]



=== TEST 30: response.exit() sends default grpc-message (200)
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            ngx.req.http_version = function() return 2 end

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(200)
        }
    }
--- request
GET /t
--- more_headers
Content-Type: application/grpc
--- error_code: 200
--- response_headers_like
Content-Length: 0
grpc-status: 0
grpc-message: OK
--- response_body chop
--- no_error_log
[error]



=== TEST 31: response.exit() sends default grpc-message (403)
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            ngx.req.http_version = function() return 2 end

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(403)
        }
    }
--- request
GET /t
--- more_headers
Content-Type: application/grpc
--- error_code: 403
--- response_headers_like
Content-Length: 0
grpc-status: 7
grpc-message: PermissionDenied
--- response_body chop
--- no_error_log
[error]



=== TEST 32: response.exit() sends default grpc-message when specifying content-type (explicit)
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(401, nil, {
                ["Content-Type"]  = "application/grpc"
            })
        }
    }
--- request
GET /t
--- error_code: 401
--- response_headers_like
Content-Length: 0
grpc-status: 16
grpc-message: Unauthenticated
--- response_body chop
--- no_error_log
[error]



=== TEST 33: response.exit() sends default grpc-message when specifying content-type (implicit)
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.set_header("Content-Type", "application/grpc")
            pdk.response.exit(401)
        }
    }
--- request
GET /t
--- error_code: 401
--- response_headers_like
Content-Length: 0
grpc-status: 16
grpc-message: Unauthenticated
--- response_body chop
--- no_error_log
[error]



=== TEST 34: response.exit() errors with grpc using table body with content-type specified (explicit)
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(401, {}, {
                ["Content-Type"]  = "application/grpc"
            })
        }
    }
--- request
GET /t
--- error_code: 500
--- error_log: table body encoding with gRPC is not supported



=== TEST 35: response.exit() errors with grpc using table body with content-type specified (implicit)
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.set_header("Content-Type", "application/grpc")
            pdk.response.exit(401, {})
        }
    }
--- request
GET /t
--- error_code: 500
--- error_log: table body encoding with gRPC is not supported



=== TEST 36: response.exit() errors with grpc using special table body with content-type specified (explicit)
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(401, { message = "I am special" }, {
                ["Content-Type"]  = "application/grpc"
            })
        }
    }
--- request
GET /t
--- error_code: 500
--- error_log: table body encoding with gRPC is not supported



=== TEST 37: response.exit() errors with grpc using special table body with content-type specified (implicit)
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.set_header("Content-Type", "application/grpc")
            pdk.response.exit(401, { message = "I am special" })
        }
    }
--- request
GET /t
--- error_code: 500
--- error_log: table body encoding with gRPC is not supported



=== TEST 38: response.exit() logs warning with grpc using table body without content-type specified
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            ngx.req.http_version = function() return 2 end

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(401, {})
        }
    }
--- request
GET /t
--- more_headers
Content-Type: application/grpc
--- response_headers_like
Content-Length: 0
grpc-status: 16
grpc-message: Unauthenticated
--- response_body chop
--- error_code: 401
--- error_log: body was removed because table body encoding with gRPC is not supported



=== TEST 39: response.exit() does not log warning with grpc using special table body without content-type specified
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            ngx.req.http_version = function() return 2 end

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.exit(401, { message = "Hello" })
        }
    }
--- request
GET /t
--- more_headers
Content-Type: application/grpc
--- response_headers_like
Content-Length: 0
grpc-status: 16
grpc-message: Hello
--- response_body chop
--- error_code: 401
--- no_error_log
[error]
