use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: upstream.set_post_args() errors if not a table
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.upstream.set_post_args, 127001)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
args must be a table
--- no_error_log
[error]



=== TEST 2: upstream.set_post_args() errors if given no arguments
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.upstream.set_post_args)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
args must be a table
--- no_error_log
[error]



=== TEST 3: upstream.set_post_args() errors if table values have bad types
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.upstream.set_post_args, {
                aaa = "foo",
                bbb = function() end,
                ccc = "bar",
            })
            ngx.say(err)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
POST /t
--- response_body
attempt to use function as query arg value
--- no_error_log
[error]



=== TEST 4: upstream.set_post_args() errors if table keys have bad types
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.upstream.set_post_args, {
                aaa = "foo",
                [true] = "what",
                ccc = "bar",
            })
            ngx.say(err)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
POST /t
--- response_body
arg keys must be strings
--- no_error_log
[error]



=== TEST 5: upstream.set_post_args() sets the Content-Type header
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                local headers = ngx.req.get_headers()
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_post_args({})
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
POST /t
--- response_body
content-type: {application/x-www-form-urlencoded}
--- no_error_log
[error]



=== TEST 6: upstream.set_post_args() accepts an empty table
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_post_args({})
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
POST /t

foo=hello%20world
--- response_body
body: {nil}
content-length: {0}
content-type: {application/x-www-form-urlencoded}
--- no_error_log
[error]



=== TEST 7: upstream.set_post_args() replaces the received post args
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_post_args({
                foo = "hello world"
            })
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
POST /t

foo=bar
--- response_body
body: {foo=hello%20world}
content-length: {17}
content-type: {application/x-www-form-urlencoded}
--- no_error_log
[error]



=== TEST 8: upstream.set_post_args() urlencodes table values
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_post_args({
                foo = "hello world"
            })
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
POST /t
--- response_body
body: {foo=hello%20world}
content-length: {17}
content-type: {application/x-www-form-urlencoded}
--- no_error_log
[error]



=== TEST 9: upstream.set_post_args() produces a deterministic lexicographical order
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_post_args({
                foo = "hello world",
                a = true,
                aa = true,
                zzz = "goodbye world",
            })
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
POST /t
--- response_body
body: {a&aa&foo=hello%20world&zzz=goodbye%20world}
content-length: {42}
content-type: {application/x-www-form-urlencoded}
--- no_error_log
[error]



=== TEST 10: upstream.set_post_args() preserves the order of array arguments
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_post_args({
                foo = "hello world",
                a = true,
                aa = { "zzz", true, true, "aaa" },
                zzz = "goodbye world",
            })
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
POST /t
--- response_body
body: {a&aa=zzz&aa&aa&aa=aaa&foo=hello%20world&zzz=goodbye%20world}
content-length: {59}
content-type: {application/x-www-form-urlencoded}
--- no_error_log
[error]



=== TEST 11: upstream.set_post_args() supports empty values
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_post_args({
                aa = "",
            })
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
POST /t
--- response_body
body: {aa=}
content-length: {3}
content-type: {application/x-www-form-urlencoded}
--- no_error_log
[error]



=== TEST 12: upstream.set_post_args() accepts empty keys
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_post_args({
                [""] = "aa",
            })
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
POST /t
--- response_body
body: {=aa}
content-length: {3}
content-type: {application/x-www-form-urlencoded}
--- no_error_log
[error]



=== TEST 13: upstream.set_post_args() urlencodes table keys
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_post_args({
                ["hello world"] = "aa",
            })
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
POST /t
--- response_body
body: {hello%20world=aa}
content-length: {16}
content-type: {application/x-www-form-urlencoded}
--- no_error_log
[error]



=== TEST 14: upstream.set_post_args() does not force a POST method
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("method: ", ngx.req.get_method())
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_post_args({
                foo = "bar",
            })
            assert(ok)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
method: GET
body: {foo=bar}
content-length: {7}
content-type: {application/x-www-form-urlencoded}
--- no_error_log
[error]
