use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: base has new_tab()
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.new_tab(0, 12)

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]



=== TEST 2: base has clear_tab()
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local t = {
                hello = "world",
                "foo",
                "bar"
            }

            sdk.clear_tab(t)

            ngx.say("hello: ", nil)
            ngx.say("#t: ", #t)
        }
    }
--- request
GET /t
--- response_body
hello: nil
#t: 0
--- no_error_log
[error]
