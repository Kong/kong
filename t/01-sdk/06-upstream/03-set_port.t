use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: upstream.set_port() errors if not a number
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.ctx.balancer_address = 8000

            local pok, err = pcall(sdk.upstream.set_port, "foo")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
port must be an integer
--- no_error_log
[error]



=== TEST 2: upstream.set_port() errors if not an integer
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.ctx.balancer_address = 8000

            local pok, err = pcall(sdk.upstream.set_port, 123.4)

            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
port must be an integer
--- no_error_log
[error]



=== TEST 3: upstream.set_port() fails if out of range
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.ctx.balancer_address = 8000

            local ok, err = sdk.upstream.set_port(-1)
            ngx.say(err)
            local ok, err = sdk.upstream.set_port(70000)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
port must be an integer between 0 and 65535: given -1
port must be an integer between 0 and 65535: given 70000
--- no_error_log
[error]



=== TEST 4: upstream.set_port() sets the balancer port
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.ctx.balancer_address = {
                port = 8000
            }

            local ok = sdk.upstream.set_port(1234)

            ngx.say(tostring(ok))
            ngx.say("port: ", ngx.ctx.balancer_address.port)
        }
    }
--- request
GET /t
--- response_body
true
port: 1234
--- no_error_log
[error]



