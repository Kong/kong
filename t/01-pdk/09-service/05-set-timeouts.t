use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
do "./t/Util.pm";

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: service.set_timeouts() errors if connect_timeout is not a number
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.set_timeouts, "2", 1, 1)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
connect_timeout must be an integer
--- no_error_log
[error]



=== TEST 2: service.set_timeouts() errors if write_timeout is not a number
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.set_timeouts, 2, "1", 1)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
write_timeout must be an integer
--- no_error_log
[error]



=== TEST 3: service.set_timeouts() errors if read_timeout is not a number
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.set_timeouts, 2, 1, "1")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
read_timeout must be an integer
--- no_error_log
[error]



=== TEST 4: service.set_timeouts() errors if connect_timeout is out of range
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.set_timeouts, -1, 1, 1)
            ngx.say(err)
            local pok, err = pcall(pdk.service.set_timeouts, 2147483647, 1, 1)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
connect_timeout must be an integer between 1 and 2147483646: given -1
connect_timeout must be an integer between 1 and 2147483646: given 2147483647
--- no_error_log
[error]



=== TEST 5: service.set_timeouts() errors if write_timeout is out of range
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.set_timeouts, 2, -1, 1)
            ngx.say(err)
            local pok, err = pcall(pdk.service.set_timeouts, 2, 2147483647, 1)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
write_timeout must be an integer between 1 and 2147483646: given -1
write_timeout must be an integer between 1 and 2147483646: given 2147483647
--- no_error_log
[error]



=== TEST 6: service.set_timeouts() errors if read_timeout is out of range
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.set_timeouts, 2, 1, -1)
            ngx.say(err)
            local pok, err = pcall(pdk.service.set_timeouts, 2, 1, 2147483647)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
read_timeout must be an integer between 1 and 2147483646: given -1
read_timeout must be an integer between 1 and 2147483646: given 2147483647
--- no_error_log
[error]



=== TEST 7: service.set_timeouts() sets the timeouts
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

             ngx.ctx.balancer_data = {
                connect_timeout = 1,
                write_timeout = 1,
                read_timeout = 1,
            }

            local ok = pdk.service.set_timeouts(2, 3, 4)
            ngx.say(tostring(ok))
            ngx.say(ngx.ctx.balancer_data.connect_timeout)
            ngx.say(ngx.ctx.balancer_data.write_timeout)
            ngx.say(ngx.ctx.balancer_data.read_timeout)
        }
    }
--- request
GET /t
--- response_body
nil
2
3
4
--- no_error_log
[error]


