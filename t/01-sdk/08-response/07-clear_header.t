use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: response.clear_header() errors if arguments are not given
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.response.clear_header)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
name must be a string
--- no_error_log
[error]



=== TEST 2: response.clear_header() errors if name is not a string
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.response.clear_header, 127001, "foo")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
name must be a string
--- no_error_log
[error]



=== TEST 3: response.clear_header() clears a given header
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.header["X-Foo"] = "bar"
            }
        }
    }
--- config
    location = /t {
        proxy_pass http://unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.clear_header("X-Foo")
        }

        body_filter_by_lua_block {
            ngx.arg[1] = "X-Foo: {" .. type(ngx.header["X-Foo"]) .. "}"
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
X-Foo: {nil}
--- no_error_log
[error]



=== TEST 4: response.clear_header() clears multiple given headers
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.header["X-Foo"] = { "hello", "world" }
            }
        }
    }
--- config
    location = /t {
        proxy_pass http://unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.clear_header("X-Foo")
        }

        body_filter_by_lua_block {
            ngx.arg[1] = "X-Foo: {" .. type(ngx.header["X-Foo"]) .. "}"
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
X-Foo: {nil}
--- no_error_log
[error]



=== TEST 5: response.clear_header() clears headers set via set_header
--- config
    location = /t {

        rewrite_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.set_header("X-Foo", "hello")
        }

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.clear_header("X-Foo")
        }

        content_by_lua_block {
            ngx.say("X-Foo: {" .. type(ngx.header["X-Foo"]) .. "}")
        }
    }
--- request
GET /t
--- response_body
X-Foo: {nil}
--- no_error_log
[error]



=== TEST 6: response.clear_header() clears headers set via set_header
--- config
    location = /t {

        rewrite_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.add_header("X-Foo", "hello")
        }

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.clear_header("X-Foo")
        }

        content_by_lua_block {
            ngx.say("X-Foo: {" .. type(ngx.header["X-Foo"]) .. "}")
        }
    }
--- request
GET /t
--- response_body
X-Foo: {nil}
--- no_error_log
[error]



=== TEST 7: response.clear_header() errors if headers have already been sent
--- config
    location = /t {
        content_by_lua_block {
            ngx.send_headers()

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = pcall(sdk.response.clear_header, "X-Foo", "")
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body
headers have been sent
--- no_error_log
[error]
