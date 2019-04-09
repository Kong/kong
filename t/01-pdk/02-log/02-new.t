use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: kong.log.new() requires a namespace
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local ok, err = pcall(pdk.log.new)
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body
namespace must be a string
--- no_error_log
[error]



=== TEST 2: kong.log.new() requires a non-empty namespace
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local ok, err = pcall(pdk.log.new, "")
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body
namespace cannot be an empty string
--- no_error_log
[error]



=== TEST 3: kong.log.new() accepts non-empty format
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local ok, err = pcall(pdk.log.new, "my_namespace", "")
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body
format cannot be an empty string if specified
--- no_error_log
[error]



=== TEST 4: kong.log.new() logs with namespaced format by default
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local log = pdk.log.new("my_namespace")

            log("hello world")
        }
    }
--- request
GET /t
--- no_response_body
--- no_error_log
[error]
--- error_log eval
qr/\[kong\] content_by_lua\(nginx\.conf:\d+\):\d+ \[my_namespace\] hello world/



=== TEST 5: kong.log.new() logs with custom format if specified
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local log = pdk.log.new("my_namespace", "%message")

            log("hello world")
        }
    }
--- request
GET /t
--- no_response_body
--- no_error_log
[error]
--- error_log eval
qr/\[kong\] hello world/
