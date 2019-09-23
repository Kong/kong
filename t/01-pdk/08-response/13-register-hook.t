use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: response.register_hook() registers a function that executes on hook
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local function a_function(status, body, headers)
                status = 404
                body = ""
                return status, body, headers
            end

            local ok1, err1 = pcall(pdk.response.register_hook, "exit", a_function)

            if not ok1 then
                ngx.say(err1)
            end

            return pdk.response.exit(200, nil, nil)
        }
    }
--- request
GET /t
--- error_code: 404
--- response_body

--- no_error_log
[error]

=== TEST 2: response.register_hook() reduces on multiple functions
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local count = 0

            local function a_function(status, body, headers)
                count = count + 1
                body = tostring(count)
                return status, body, headers
            end

            pdk.response.register_hook("exit", a_function)
            pdk.response.register_hook("exit", a_function)
            pdk.response.register_hook("exit", a_function)
            pdk.response.register_hook("exit", a_function)

            return pdk.response.exit(200, nil, nil)
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body chop
4
--- no_error_log
[error]

=== TEST 3: response.register_hook() accepts a context
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local _M = {}

            function _M:new()
                self.msg = "Hello World"
                pdk.response.register_hook("exit", self.some_hook, self)
            end

            function _M:some_hook(status, body, headers)
                return status, self.msg, headers
            end

            local foo = _M:new()

            return pdk.response.exit(200, nil, nil)
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body chop
Hello World
--- no_error_log
[error]
