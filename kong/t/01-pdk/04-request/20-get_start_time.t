use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use Test::Nginx::Socket::Lua::Stream;
do "./t/Util.pm";

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_start_time() uses ngx.ctx.KONG_PROCESSING_START when available
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.ctx.KONG_PROCESSING_START = 10001
            local start_time = pdk.request.get_start_time()

            ngx.say("start_time: ", start_time)
            ngx.say("type: ", type(start_time))
        }
    }
--- request
GET /t/request-path
--- response_body
start_time: 10001
type: number
--- no_error_log
[error]



=== TEST 2: request.get_start_time() falls back to ngx.req.start_time() as needed
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.ctx.KONG_PROCESSING_START = nil
            local ngx_start = ngx.req.start_time() * 1000
            local pdk_start = pdk.request.get_start_time()

            if pdk_start ~= ngx_start then
                ngx.status = 500
                ngx.say("bad result from request.get_start_time(): ", pdk_start)
                return ngx.exit(500)
            end

            ngx.say("start_time: ", pdk_start)
            ngx.say("type: ", type(pdk_start))
        }
    }
--- request
GET /t/request-path
--- response_body_like
^start_time: \d+
type: number
--- no_error_log
[error]



=== TEST 3: request.get_start_time() works in the stream subsystem
--- stream_server_config
    content_by_lua_block {
        local PDK = require "kong.pdk"
        local pdk = PDK.new()

        local start_time = pdk.request.get_start_time()
        ngx.say("ngx.req: ", start_time, " ", type(start_time))

        ngx.ctx.KONG_PROCESSING_START = 1000
        start_time = pdk.request.get_start_time()
        ngx.say("ngx.ctx: ", start_time, " ", type(start_time))
    }
--- stream_response_like chomp
ngx.req: \d+ number
ngx.ctx: 1000 number
--- no_error_log
[error]
