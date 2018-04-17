use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: upstream.clear_header() errors if arguments are not given
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.upstream.clear_header)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
header must be a string
--- no_error_log
[error]




=== TEST 2: upstream.clear_header() errors if header is not a string
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.upstream.clear_header, 127001, "foo")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
header must be a string
--- no_error_log
[error]



=== TEST 3: upstream.clear_header() clears a given header
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: {" .. tostring(ngx.req.get_headers()["X-Foo"]) .. "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.clear_header("X-Foo")
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- more_headers
X-Foo: bar
--- response_body
X-Foo: {nil}
--- no_error_log
[error]



=== TEST 4: upstream.clear_header() clears multiple given headers
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: {" .. tostring(ngx.req.get_headers()["X-Foo"]) .. "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.clear_header("X-Foo")
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- more_headers
X-Foo: hello
X-Foo: world
--- response_body
X-Foo: {nil}
--- no_error_log
[error]



=== TEST 5: upstream.clear_header() clears headers set via set_header
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: {" .. tostring(ngx.req.get_headers()["X-Foo"]) .. "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_header("X-Foo", "hello")
            assert(ok)
            local ok, err = sdk.upstream.clear_header("X-Foo")
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
X-Foo: {nil}
--- no_error_log
[error]




=== TEST 6: upstream.clear_header() clears headers set via add_header
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: {" .. tostring(ngx.req.get_headers()["X-Foo"]) .. "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_header("X-Foo", "hello")
            assert(ok)
            local ok, err = sdk.upstream.add_header("X-Foo", "world")
            assert(ok)
            local ok, err = sdk.upstream.clear_header("X-Foo")
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
X-Foo: {nil}
--- no_error_log
[error]



