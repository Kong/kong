use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: response.add_header() errors if arguments are not given
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = pcall(sdk.response.add_header)
            if not ok then
                ngx.ctx.err = err
            end
        }

        body_filter_by_lua_block {
            ngx.arg[1] = ngx.ctx.err
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
header name must be a string
--- no_error_log
[error]



=== TEST 2: response.add_header() errors if name is not a string
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = pcall(sdk.response.add_header, 127001, "foo")
            if not ok then
                ngx.ctx.err = err
            end
        }

        body_filter_by_lua_block {
            ngx.arg[1] = ngx.ctx.err
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
header name must be a string
--- no_error_log
[error]



=== TEST 3: response.add_header() errors if value is not a supported one
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = pcall(sdk.response.add_header, "foo", {})
            if not ok then
                ngx.ctx.err = err
            end
        }

        body_filter_by_lua_block {
            ngx.arg[1] = ngx.ctx.err
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
invalid value for "foo": got table, expected string, number or boolean
--- no_error_log
[error]



=== TEST 4: response.add_header() errors if value is not given
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = pcall(sdk.response.add_header, "foo")
            if not ok then
                ngx.ctx.err = err
            end
        }

        body_filter_by_lua_block {
            ngx.arg[1] = ngx.ctx.err
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
invalid value for "foo": got nil, expected string, number or boolean
--- no_error_log
[error]



=== TEST 5: response.add_header() sets a header in the downstream response
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.add_header("X-Foo", "hello world")
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



=== TEST 6: response.add_header() adds two headers to an downstream response
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.add_header("X-Foo", "hello")
            sdk.response.add_header("X-Foo", "world")
        }

        body_filter_by_lua_block {
            local foo_headers = ngx.resp.get_headers()["X-Foo"]
            local response = {}
            for i, v in ipairs(foo_headers) do
                response[i] = "X-Foo: {" .. tostring(v) .. "}"
            end

            ngx.arg[1] = table.concat(response, "\n")
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
X-Foo: {hello}
X-Foo: {world}
--- no_error_log
[error]



=== TEST 7: response.add_header() preserves headers with that name if any exist
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.header["X-Foo"] = { "bla bla", "baz" }
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

            sdk.response.add_header("X-Foo", "hello world")
        }

        body_filter_by_lua_block {
            local foo_headers = ngx.resp.get_headers()["X-Foo"]
            local response = {}
            for i, v in ipairs(foo_headers) do
                response[i] = "X-Foo: {" .. tostring(v) .. "}"
            end

            ngx.arg[1] = table.concat(response, "\n")
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
X-Foo: {bla bla}
X-Foo: {baz}
X-Foo: {hello world}
--- no_error_log
[error]



=== TEST 8: response.add_header() can set to an empty string
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
            }

            header_filter_by_lua_block {
                local SDK = require "kong.sdk"
                local sdk = SDK.new()

                sdk.response.add_header("X-Foo", "")
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
