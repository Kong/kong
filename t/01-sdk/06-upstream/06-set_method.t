use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: upstream.set_method() errors if not a string
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.upstream.set_method, 127001)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
method must be a string
--- no_error_log
[error]



=== TEST 2: upstream.set_method() errors if given no arguments
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.upstream.set_method)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
method must be a string
--- no_error_log
[error]



=== TEST 3: upstream.set_method() fails if given an invalid method
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_method("FOO")

            ngx.say(tostring(ok))
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
nil
invalid method: FOO
--- no_error_log
[error]



=== TEST 4: upstream.set_method() demands uppercase methods
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_method("get")

            ngx.say(tostring(ok))
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
nil
invalid method: get
--- no_error_log
[error]



=== TEST 5: upstream.set_method() sets the request method to GET
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_method("GET")
            assert(ok, err)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
method: GET
--- no_error_log
[error]



=== TEST 6: upstream.set_method() sets the request method to HEAD
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.log(ngx.ERR, "method: ", ngx.req.get_method())
            }
        }
    }
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_method("HEAD")
            assert(ok, err)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
--- error_log
method: HEAD



=== TEST 7: upstream.set_method() sets the request method to PUT
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_method("PUT")
            assert(ok, err)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
method: PUT
--- no_error_log
[error]



=== TEST 8: upstream.set_method() sets the request method to POST
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_method("POST")
            assert(ok, err)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
method: POST
--- no_error_log
[error]



=== TEST 9: upstream.set_method() sets the request method to DELETE
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_method("DELETE")
            assert(ok, err)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
method: DELETE
--- no_error_log
[error]



=== TEST 10: upstream.set_method() sets the request method to OPTIONS
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_method("OPTIONS")
            assert(ok, err)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
method: OPTIONS
--- no_error_log
[error]



=== TEST 11: upstream.set_method() sets the request method to MKCOL
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_method("MKCOL")
            assert(ok, err)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
method: MKCOL
--- no_error_log
[error]



=== TEST 12: upstream.set_method() sets the request method to COPY
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_method("COPY")
            assert(ok, err)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
method: COPY
--- no_error_log
[error]



=== TEST 13: upstream.set_method() sets the request method to MOVE
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_method("MOVE")
            assert(ok, err)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
method: MOVE
--- no_error_log
[error]



=== TEST 14: upstream.set_method() sets the request method to PROPFIND
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_method("PROPFIND")
            assert(ok, err)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
method: PROPFIND
--- no_error_log
[error]



=== TEST 15: upstream.set_method() sets the request method to PROPPATCH
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_method("PROPPATCH")
            assert(ok, err)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
method: PROPPATCH
--- no_error_log
[error]



=== TEST 16: upstream.set_method() sets the request method to LOCK
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_method("LOCK")
            assert(ok, err)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
method: LOCK
--- no_error_log
[error]



=== TEST 17: upstream.set_method() sets the request method to UNLOCK
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_method("UNLOCK")
            assert(ok, err)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
method: UNLOCK
--- no_error_log
[error]



=== TEST 18: upstream.set_method() sets the request method to PATCH
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_method("PATCH")
            assert(ok, err)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
method: PATCH
--- no_error_log
[error]



=== TEST 19: upstream.set_method() sets the request method to TRACE (for which Nginx always returns 405)
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("this never runs")
            }
        }
    }
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_method("TRACE")
            assert(ok, err)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- error_code: 405
--- response_body_like chomp
405 Not Allowed
--- no_error_log
[error]
