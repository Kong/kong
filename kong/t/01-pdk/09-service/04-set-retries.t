use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
do "./t/Util.pm";

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: service.set_retries() errors if port is not a number
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.set_retries, "2")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
retries must be an integer
--- no_error_log
[error]



=== TEST 1: service.set_retries() errors if port is not an integer
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.set_retries, 1.23)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
retries must be an integer
--- no_error_log
[error]



=== TEST 3: service.set_target() errors if port is out of range
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.set_retries, -1)
            ngx.say(err)
            local pok, err = pcall(pdk.service.set_retries, 32768)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
retries must be an integer between 0 and 32767: given -1
retries must be an integer between 0 and 32767: given 32768
--- no_error_log
[error]



=== TEST 4: service.set_retries() sets ngx.ctx.balancer_data.retries
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {

        set $upstream_host '';

        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.ctx.balancer_data = {
                retries = 1
            }

            local ok = pdk.service.set_retries(123)

            ngx.say(tostring(ok))
            ngx.say("retries: ", ngx.ctx.balancer_data.retries)
        }
    }
--- request
GET /t
--- response_body
nil
retries: 123
--- no_error_log
[error]


