use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: upstream.set_path() errors if not a string
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.upstream.set_path, 127001)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
path must be a string
--- no_error_log
[error]



=== TEST 2: upstream.set_path() fails if path doesn't start with "/"
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_path("foo")

            ngx.say(tostring(ok))
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
nil
path must start with /
--- no_error_log
[error]



=== TEST 3: upstream.set_path() works from access phase
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /foo {
            content_by_lua_block {
                ngx.say("this is /foo")
            }
        }
    }
--- config
    location = /t {

        set $upstream_uri '/t';

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_path("/foo")
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080$upstream_uri;
    }
--- request
GET /t
--- response_body
this is /foo
--- no_error_log
[error]



=== TEST 4: upstream.set_path() works from rewrite phase
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /foo {
            content_by_lua_block {
                ngx.say("this is /foo")
            }
        }
    }
--- config
    location = /t {

        set $upstream_uri '/t';

        rewrite_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_path("/foo")
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080$upstream_uri;
    }
--- request
GET /t
--- response_body
this is /foo
--- no_error_log
[error]
