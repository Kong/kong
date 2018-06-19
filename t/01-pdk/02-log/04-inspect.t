use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 4);

run_tests();

__DATA__

=== TEST 1: kong.log.inspect() pretty-prints a table
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log.inspect({ hello = "world" })
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
hello = "world"
--- no_error_log
[error]
[warn]



=== TEST 2: kong.log.inspect() has its own format
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local function my_func()
                pdk.log.inspect({ hello = "world" })
            end

            my_func()
        }
    }
--- request
GET /t
--- no_response_body
--- error_log eval
qr/\[kong\] content_by_lua\(nginx\.conf:\d+\):my_func:6 \{/
--- no_error_log
[error]
[warn]



=== TEST 3: kong.log.inspect() accepts variadic arguments
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log.inspect({ hello = "world" }, { bye = "world" })
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
hello = "world"
bye = "world"
--- no_error_log
[error]



=== TEST 4: kong.log.inspect.on|off() disables inspect for a facility
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log.inspect("log me")
            pdk.log.inspect.off()
            pdk.log.inspect("hidden")
            pdk.log.inspect.on()
            pdk.log.inspect("log again")
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
log me
log again
--- no_error_log
hidden



=== TEST 5: log.inspect.on|off() enables specific facility's inspect
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local log_1 = pdk.log.new("my_namespace")
            local log_2 = pdk.log.new("my_namespace")

            log_1.inspect.off()
            log_1.inspect("hidden")

            log_2.inspect("log me")
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
log me
--- no_error_log
hidden
[error]



=== TEST 6: log.inspect() custom facility does not log namespace
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local log = pdk.log.new("my_namespace")

            log.inspect("hello")
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
hello
--- no_error_log
my_namespace
[error]



=== TEST 7: log.inspect() concatenates argument with a space
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local log = pdk.log.new("my_namespace")

            log.inspect("hello", "world")
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
"hello" "world"
--- no_error_log
my_namespace
[error]
