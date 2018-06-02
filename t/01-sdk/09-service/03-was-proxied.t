use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: service.was_proxied() returns true if ngx.ctx.KONG_PROXIED is true
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.ctx.KONG_PROXIED = true
            local pok, ok = pcall(sdk.service.was_proxied)
            ngx.say(tostring(ok))
        }
    }
--- request
GET /t
--- response_body
true
--- no_error_log
[error]



=== TEST 2: service.was_proxied() returns false if ngx.ctx.KONG_PROXIED not set
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, ok = pcall(sdk.service.was_proxied)
            ngx.say(tostring(ok))
        }
    }
--- request
GET /t
--- response_body
false
--- no_error_log
[error]
