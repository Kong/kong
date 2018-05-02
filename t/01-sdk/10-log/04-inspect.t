use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 4);

run_tests();

__DATA__

=== TEST 1: kong.log.inspect() pretty-prints a table
--- config
    location /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.log.inspect({ hello = "world" })
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
--- config
    location /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local function my_func()
                sdk.log.inspect({ hello = "world" })
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
--- config
    location /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.log.inspect({ hello = "world" }, { bye = "world" })
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
--- config
    location /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.log.inspect("log me")
            sdk.log.inspect.off()
            sdk.log.inspect("hidden")
            sdk.log.inspect.on()
            sdk.log.inspect("log again")
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
--- config
    location /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local log_1 = sdk.log.new("my_namespace")
            local log_2 = sdk.log.new("my_namespace")

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
--- config
    location /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local log = sdk.log.new("my_namespace")

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
