use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: service.request.set_query_args() errors if not a table
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.service.request.set_query_args, 127001)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
args must be a table
--- no_error_log
[error]



=== TEST 2: service.request.set_query_args() errors if given no arguments
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.service.request.set_query_args)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
args must be a table
--- no_error_log
[error]



=== TEST 3: service.request.set_query_args() errors if table values have bad types
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.service.request.set_query_args, {
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



=== TEST 4: service.request.set_query_args() errors if table keys have bad types
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.service.request.set_query_args, {
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



=== TEST 5: service.request.set_query_args() accepts an empty table
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("query: {", ngx.var.args, "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.service.request.set_query_args({})

        }

        proxy_pass http://unix:/$TEST_NGINX_HTML_DIR/nginx.sock;
    }
--- request
GET /t
--- response_body
query: {nil}
--- no_error_log
[error]



=== TEST 6: service.request.set_query_args() replaces the received post args
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("query: {", ngx.var.args, "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.service.request.set_query_args({
                foo = "hello world"
            })

        }

        proxy_pass http://unix:/$TEST_NGINX_HTML_DIR/nginx.sock;
    }
--- request
GET /t?foo=bar
--- response_body
query: {foo=hello%20world}
--- no_error_log
[error]



=== TEST 7: service.request.set_query_args() urlencodes table values
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("query: {", ngx.var.args, "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.service.request.set_query_args({
                foo = "hello world"
            })

        }

        proxy_pass http://unix:/$TEST_NGINX_HTML_DIR/nginx.sock;
    }
--- request
POST /t
--- response_body
query: {foo=hello%20world}
--- no_error_log
[error]



=== TEST 8: service.request.set_query_args() produces a deterministic lexicographical order
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("query: {", ngx.var.args, "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.service.request.set_query_args({
                foo = "hello world",
                a = true,
                aa = true,
                zzz = "goodbye world",
            })

        }

        proxy_pass http://unix:/$TEST_NGINX_HTML_DIR/nginx.sock;
    }
--- request
POST /t
--- response_body
query: {a&aa&foo=hello%20world&zzz=goodbye%20world}
--- no_error_log
[error]



=== TEST 9: service.request.set_query_args() preserves the order of array arguments
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("query: {", ngx.var.args, "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.service.request.set_query_args({
                foo = "hello world",
                a = true,
                aa = { "zzz", true, true, "aaa" },
                zzz = "goodbye world",
            })

        }

        proxy_pass http://unix:/$TEST_NGINX_HTML_DIR/nginx.sock;
    }
--- request
POST /t
--- response_body
query: {a&aa=zzz&aa&aa&aa=aaa&foo=hello%20world&zzz=goodbye%20world}
--- no_error_log
[error]



=== TEST 10: service.request.set_query_args() supports empty values
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("query: {", ngx.var.args, "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.service.request.set_query_args({
                aa = "",
            })

        }

        proxy_pass http://unix:/$TEST_NGINX_HTML_DIR/nginx.sock;
    }
--- request
POST /t
--- response_body
query: {aa=}
--- no_error_log
[error]



=== TEST 11: service.request.set_query_args() accepts empty keys
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("query: {", ngx.var.args, "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.service.request.set_query_args({
                [""] = "aa",
            })

        }

        proxy_pass http://unix:/$TEST_NGINX_HTML_DIR/nginx.sock;
    }
--- request
POST /t
--- response_body
query: {=aa}
--- no_error_log
[error]



=== TEST 12: service.request.set_query_args() urlencodes table keys
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("query: {", ngx.var.args, "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.service.request.set_query_args({
                ["hello world"] = "aa",
            })

        }

        proxy_pass http://unix:/$TEST_NGINX_HTML_DIR/nginx.sock;
    }
--- request
POST /t
--- response_body
query: {hello%20world=aa}
--- no_error_log
[error]
