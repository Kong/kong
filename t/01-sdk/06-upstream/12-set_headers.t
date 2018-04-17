use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: upstream.set_headers() errors if arguments are not given
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.upstream.set_headers)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
headers must be a table
--- no_error_log
[error]




=== TEST 2: upstream.set_headers() errors if header is not a string
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.upstream.set_headers, 127001)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
headers must be a table
--- no_error_log
[error]



=== TEST 3: upstream.set_headers() with "Host" sets ngx.ctx.balancer_address.host
--- config
    location = /t {

        set $upstream_host '';

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.ctx.balancer_address = {
                host = "foo.xyz"
            }

            local ok = sdk.upstream.set_headers({["Host"] = "example.com"})

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



=== TEST 4: upstream.set_headers() with "host" has special Host-behavior in lowercase as well
--- config
    location = /t {

        set $upstream_host '';

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.ctx.balancer_address = {
                host = "foo.xyz"
            }

            local ok = sdk.upstream.set_headers({["host"] = "example.com"})

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



=== TEST 5: upstream.set_headers() with "Host" sets Host header sent to upstream
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

            local ok, err = sdk.upstream.set_headers({["Host"] = "example.com"})
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



=== TEST 6: upstream.set_headers() sets a header in the upstream request
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

            local ok, err = sdk.upstream.set_headers({["X-Foo"] = "hello world"})
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



=== TEST 7: upstream.set_headers() replaces all headers with that name if any exist
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: ", tostring(ngx.req.get_headers()["X-Foo"]))
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_headers({["X-Foo"] = "hello world"})
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
X-Foo: hello world
--- no_error_log
[error]



=== TEST 8: upstream.set_headers() can set to an empty string
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

            local ok, err = sdk.upstream.set_headers({["X-Foo"] = ""})
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



=== TEST 9: upstream.set_headers() ignores spaces in the beginning of value
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

            local ok, err = sdk.upstream.set_headers({["X-Foo"] = "     hello"})
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



=== TEST 10: upstream.set_headers() ignores spaces in the end of value
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

            local ok, err = sdk.upstream.set_headers({["X-Foo"] = "hello       "})
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



=== TEST 11: upstream.set_headers() can differentiate empty string from unset
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

            local ok, err = sdk.upstream.set_headers({["X-Foo"] = ""})
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



=== TEST 12: upstream.set_headers() fails if key is not a string
--- http_config
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_headers({[2] = "foo"})
            assert(ok == nil)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
invalid key "2": got number, expected string
--- no_error_log
[error]



=== TEST 13: upstream.set_headers() fails if value is of a bad type
--- http_config
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_headers({["foo"] = 2})
            assert(ok == nil)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
invalid value in "foo": got number, expected string
--- no_error_log
[error]



=== TEST 14: upstream.set_headers() fails if array element is of a bad type
--- http_config
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_headers({["foo"] = {2}})
            assert(ok == nil)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
invalid value in array "foo": got number, expected string
--- no_error_log
[error]



=== TEST 15: upstream.set_headers() ignores non-sequence elements in arrays
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

            local ok, err = sdk.upstream.set_headers({
                ["X-Foo"] = {
                    "hello",
                    "world",
                    ["foo"] = "bar",
                }
            })
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



=== TEST 16: upstream.set_headers() removes headers when given an empty array
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                local foo_headers = ngx.req.get_headers()["X-Foo"] or {}
                for _, v in ipairs(foo_headers) do
                    ngx.say("X-Foo: {" .. tostring(v) .. "}")
                end
                ngx.say(":)")
            }
        }
    }
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_headers({
                ["X-Foo"] = {}
            })
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
:)
--- no_error_log
[error]



=== TEST 17: upstream.set_headers() replaces every header of a given name
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                local foo_headers = ngx.req.get_headers()["X-Foo"] or {}
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

            local ok, err = sdk.upstream.set_headers({
                ["X-Foo"] = { "xxx", "yyy", "zzz" }
            })
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- more_headers
X-Foo: aaa
X-Foo: bbb
X-Foo: ccc
X-Foo: ddd
X-Foo: eee
--- response_body
X-Foo: {xxx}
X-Foo: {yyy}
X-Foo: {zzz}
--- no_error_log
[error]



=== TEST 18: upstream.set_headers() accepts an empty table
--- http_config
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_headers({})
            ngx.say(ok)
        }
    }
--- request
GET /t
--- response_body
true
--- no_error_log
[error]



