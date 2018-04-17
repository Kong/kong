use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: upstream.add_header() errors if arguments are not given
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.upstream.add_header)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
header must be a string
--- no_error_log
[error]




=== TEST 2: upstream.add_header() errors if header is not a string
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.upstream.add_header, 127001, "foo")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
header must be a string
--- no_error_log
[error]



=== TEST 3: upstream.add_header() errors if value is not a string
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.upstream.add_header, "foo", 123456)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
value must be a string
--- no_error_log
[error]



=== TEST 4: upstream.add_header() errors if value is not given
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.upstream.add_header, "foo")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
value must be a string
--- no_error_log
[error]



=== TEST 5: upstream.add_header("Host") sets ngx.ctx.balancer_address.host
--- config
    location = /t {

        set $upstream_host '';

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.ctx.balancer_address = {
                host = "foo.xyz"
            }

            local ok = sdk.upstream.add_header("Host", "example.com")

            ngx.say(tostring(ok))
            ngx.say("host: ", ngx.ctx.balancer_address.host)
        }
    }
--- request
GET /t
--- response_body
true
host: example.com
--- no_error_log
[error]



=== TEST 6: upstream.add_header("host") has special Host-behavior in lowercase as well
--- config
    location = /t {

        set $upstream_host '';

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.ctx.balancer_address = {
                host = "foo.xyz"
            }

            local ok = sdk.upstream.add_header("host", "example.com")

            ngx.say(tostring(ok))
            ngx.say("host: ", ngx.ctx.balancer_address.host)
        }
    }
--- request
GET /t
--- response_body
true
host: example.com
--- no_error_log
[error]



=== TEST 7: upstream.add_header("Host") sets Host header sent to upstream
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("host: ", ngx.req.get_headers()["Host"])
            }
        }
    }
--- config
    location = /t {

        set $upstream_host '';

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.ctx.balancer_address = {
                host = "foo.xyz"
            }

            local ok, err = sdk.upstream.add_header("Host", "example.com")
            assert(ok)
        }

        proxy_set_header Host $upstream_host;
        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
host: example.com
--- no_error_log
[error]



=== TEST 8: upstream.add_header("Host") cannot add two hosts
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("host: ", ngx.req.get_headers()["Host"])
            }
        }
    }
--- config
    location = /t {

        set $upstream_host '';

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.ctx.balancer_address = {
                host = "foo.xyz"
            }

            local ok, err = sdk.upstream.add_header("Host", "example.com")
            assert(ok)
            local ok, err = sdk.upstream.add_header("Host", "example2.com")
            assert(ok)
        }

        proxy_set_header Host $upstream_host;
        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
host: example2.com
--- no_error_log
[error]



=== TEST 9: upstream.add_header() sets a header in the upstream request
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: {" .. ngx.req.get_headers()["X-Foo"] .. "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.add_header("X-Foo", "hello world")
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
X-Foo: {hello world}
--- no_error_log
[error]



=== TEST 10: upstream.add_header() adds two headers to an upstream request
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                local foo_headers = ngx.req.get_headers()["X-Foo"]
                for _, v in ipairs(foo_headers) do
                    ngx.say("X-Foo: {" .. tostring(v) .. "}")
                end
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.add_header("X-Foo", "hello")
            assert(ok)
            local ok, err = sdk.upstream.add_header("X-Foo", "world")
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
X-Foo: {hello}
X-Foo: {world}
--- no_error_log
[error]



=== TEST 11: upstream.add_header() preserves headers with that name if any exist
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                local foo_headers = ngx.req.get_headers()["X-Foo"]
                for _, v in ipairs(foo_headers) do
                    ngx.say("X-Foo: {" .. tostring(v) .. "}")
                end
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.add_header("X-Foo", "hello world")
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- more_headers
X-Foo: bla bla
X-Foo: baz
--- response_body
X-Foo: {bla bla}
X-Foo: {baz}
X-Foo: {hello world}
--- no_error_log
[error]



=== TEST 12: upstream.add_header() can set to an empty string
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: {" .. ngx.req.get_headers()["X-Foo"] .. "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.add_header("X-Foo", "")
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
X-Foo: {}
--- no_error_log
[error]



=== TEST 13: upstream.add_header() ignores spaces in the beginning of value
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: {" .. ngx.req.get_headers()["X-Foo"] .. "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.add_header("X-Foo", "     hello")
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
X-Foo: {hello}
--- no_error_log
[error]



=== TEST 14: upstream.add_header() ignores spaces in the end of value
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: {" .. ngx.req.get_headers()["X-Foo"] .. "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.add_header("X-Foo", "hello       ")
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
X-Foo: {hello}
--- no_error_log
[error]



=== TEST 15: upstream.add_header() can differentiate empty string from unset
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                local headers = ngx.req.get_headers()
                ngx.say("X-Foo: {" .. headers["X-Foo"] .. "}")
                ngx.say("X-Bar: {" .. tostring(headers["X-Bar"]) .. "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.add_header("X-Foo", "")
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
X-Foo: {}
X-Bar: {nil}
--- no_error_log
[error]



