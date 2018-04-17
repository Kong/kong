use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: upstream.set_query() errors if not a string
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.upstream.set_query, 127001)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
query must be a string
--- no_error_log
[error]



=== TEST 2: upstream.set_query() errors if given no arguments
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.upstream.set_query)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
query must be a string
--- no_error_log
[error]



=== TEST 3: upstream.set_query() accepts an empty string
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("query: {", tostring(ngx.var.args), "}")
            }
        }
    }
--- config
    location = /t {

        set $upstream_host '';

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_query("")
            assert(ok)
        }

        proxy_set_header Host $upstream_host;
        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
query: {nil}
--- no_error_log
[error]



=== TEST 4: upstream.set_query() sets the query string
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("query: {", tostring(ngx.var.args), "}")
            }
        }
    }
--- config
    location = /t {

        set $upstream_host '';

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_query("foo=bar&bla&baz=hello%20world")
            assert(ok)
        }

        proxy_set_header Host $upstream_host;
        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t
--- response_body
query: {foo=bar&bla&baz=hello%20world}
--- no_error_log
[error]



=== TEST 5: upstream.set_query() replaces any existing query string
--- http_config
    server {
        listen 127.0.0.1:9080;

        location /t {
            content_by_lua_block {
                ngx.say("query: {", tostring(ngx.var.args), "}")
            }
        }
    }
--- config
    location = /t {

        set $upstream_host '';

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = sdk.upstream.set_query("foo=bar&bla&baz=hello%20world")
            assert(ok)
        }

        proxy_set_header Host $upstream_host;
        proxy_pass http://127.0.0.1:9080;
    }
--- request
GET /t?bla&baz=hello%20mars&something_else=is_set
--- response_body
query: {foo=bar&bla&baz=hello%20world}
--- no_error_log
[error]



