use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
do "./t/Util.pm";

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: response.get_raw_body() gets raw body
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            ngx.say("Hello, Content by Lua Block")
        }
        body_filter_by_lua_block {
            ngx.ctx.called = (ngx.ctx.called or 0) + 1

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local body = pdk.response.get_raw_body()
            if body then
                pdk.response.set_raw_body(body .. "Enhanced by Body Filter\nCalled "
                                               .. ngx.ctx.called .. " times\n")
            end
        }
    }
--- request
GET /t
--- response_body
Hello, Content by Lua Block
Enhanced by Body Filter
Called 2 times
--- no_error_log
[error]



=== TEST 2: response.get_raw_body() gets raw body when chunked
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        echo -n 'Hello, ';
        echo 'Content by Lua Block';

        body_filter_by_lua_block {
            ngx.ctx.called = (ngx.ctx.called or 0) + 1

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local body = pdk.response.get_raw_body()
            if body then
                if body == "Hello, Content by Lua Block\n" then
                    pdk.response.set_raw_body(body .. "Enhanced by Body Filter\nCalled " .. ngx.ctx.called ..  " times\n")
                else
                    pdk.response.set_raw_body("Wrong body")
                end
            end
        }
    }
--- request
GET /t
--- response_body
Hello, Content by Lua Block
Enhanced by Body Filter
Called 3 times
--- no_error_log
[error]



=== TEST 3: response.get_raw_body() calls multiple times
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            ngx.print("hello, world!\n")
        }
        body_filter_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            -- call pdk.response.get_raw_body() multiple times
            local body = pdk.response.get_raw_body()
            assert(body == "hello, world!\n")
            local body = pdk.response.get_raw_body()
            assert(body == "hello, world!\n")
            local body = pdk.response.get_raw_body()
            assert(body == "hello, world!\n")
        }
    }
--- request
GET /t
--- response_body
hello, world!
--- no_error_log
[error]
