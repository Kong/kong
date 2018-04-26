use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: upstream.set_body_args() errors if args is not a table
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.upstream.set_body_args, 127001)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
args must be a table
--- no_error_log
[error]



=== TEST 2: upstream.set_body_args() errors if given no arguments
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.upstream.set_body_args)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
args must be a table
--- no_error_log
[error]



=== TEST 3: upstream.set_body_args() errors if mime is not a string
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.upstream.set_body_args, {}, 123)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
mime must be a string
--- no_error_log
[error]



=== TEST 4: upstream.set_body_args() sets arguments with application/x-www-form-urlencoded
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                ngx.say("Content-Type: ", ngx.req.get_headers()["Content-Type"])
                ngx.say(ngx.req.get_body_data())
            }
        }
    }
--- config
    location = /t {

        set $upstream_host '';

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.upstream.set_body_args({
                test = "post",
                aaa = "zzz",
            }, "application/x-www-form-urlencoded")

        }

        proxy_set_header Host $upstream_host;
        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
Content-Type: application/x-www-form-urlencoded
aaa=zzz&test=post
--- no_error_log
[error]




=== TEST 5: upstream.set_body_args() sets arguments with application/x-www-form-urlencoded
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                ngx.say("Content-Type: ", ngx.req.get_headers()["Content-Type"])
                ngx.say(ngx.req.get_body_data())
            }
        }
    }
--- config
    location = /t {

        set $upstream_host '';

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.upstream.set_body_args({
                test = "post",
                aaa = "zzz",
            }, "application/x-www-form-urlencoded")

        }

        proxy_set_header Host $upstream_host;
        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
Content-Type: application/x-www-form-urlencoded
aaa=zzz&test=post
--- no_error_log
[error]




