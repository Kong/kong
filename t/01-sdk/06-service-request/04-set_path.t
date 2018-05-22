use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: service.request.set_path() errors if not a string
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.service.request.set_path, 127001)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
path must be a string
--- no_error_log
[error]



=== TEST 2: service.request.set_path() errors if path doesn't start with "/"
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.service.request.set_path, "foo")

            ngx.say(tostring(pok))
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
false
path must start with /
--- no_error_log
[error]



=== TEST 3: service.request.set_path() works from access phase
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

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

            sdk.service.request.set_path("/foo")
        }

        proxy_pass http://unix:/$TEST_NGINX_HTML_DIR/nginx.sock:$upstream_uri;
    }
--- request
GET /t
--- response_body
this is /foo
--- no_error_log
[error]



=== TEST 4: service.request.set_path() works from rewrite phase
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

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

            sdk.service.request.set_path("/foo")
        }

        proxy_pass http://unix:/$TEST_NGINX_HTML_DIR/nginx.sock:$upstream_uri;
    }
--- request
GET /t
--- response_body
this is /foo
--- no_error_log
[error]
