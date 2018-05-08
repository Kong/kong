use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: response.set_header() errors if arguments are not given
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local _, err = pcall(sdk.response.set_header)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
name must be a string
--- no_error_log
[error]



=== TEST 2: response.set_header() errors if name is not a string
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.response.set_header, 127001, "foo")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
name must be a string
--- no_error_log
[error]



=== TEST 3: response.set_header() errors if value is not a string
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local _, err = pcall(sdk.response.set_header, "foo", 123456)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
value must be a string
--- no_error_log
[error]



=== TEST 4: response.set_header() errors if value is not given
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local _, err = pcall(sdk.response.set_header, "foo")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
value must be a string
--- no_error_log
[error]



=== TEST 5: response.set_header() sets a header in the downstream response
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.set_header("X-Foo", "hello world")
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil
        }

        body_filter_by_lua_block {
            ngx.arg[1] = "X-Foo: " .. ngx.header["X-Foo"]
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
X-Foo: hello world
--- no_error_log
[error]



=== TEST 6: response.set_header() replaces all headers with that name if any exist
--- config
    location = /t {
        access_by_lua_block {
            ngx.header["X-Foo"] = { "First", "Second" }
        }

        content_by_lua_block {
            local headers = ngx.resp.get_headers()

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.set_header("X-Foo", "hello world")

            local new_headers = ngx.resp.get_headers()

            ngx.say("type: ", type(headers["X-Foo"]))
            ngx.say("size: ", #headers["X-Foo"])

            ngx.print("type: ", type(new_headers["X-Foo"]))
        }
    }
--- request
GET /t
--- response_body chop
type: table
size: 2
type: string
--- no_error_log
[error]



=== TEST 7: response.set_header() can set to an empty string
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                local SDK = require "kong.sdk"
                local sdk = SDK.new()

                sdk.response.set_header("X-Foo", "")
            }
        }
    }
--- config
    location = /t {
        proxy_pass http://unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil
        }

        body_filter_by_lua_block {
            ngx.arg[1] = "type: " .. type(ngx.resp.get_headers()["X-Foo"]) .. "\n" ..
                         "X-Foo: {" .. ngx.resp.get_headers()["X-Foo"] .. "}"
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
type: string
X-Foo: {}
--- no_error_log
[error]



=== TEST 8: response.set_header() errors if headers have already been sent
--- config
    location = /t {
        content_by_lua_block {
            ngx.send_headers()

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = pcall(sdk.response.set_header, "X-Foo", "")
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
