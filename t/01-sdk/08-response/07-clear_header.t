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
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = pcall(sdk.response.clear_header)
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
header must be a string
--- no_error_log
[error]



=== TEST 2: response.clear_header() errors if name is not a string
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local po, err = pcall(sdk.response.clear_header, 127001, "foo")
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
header must be a string
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
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.set_header("X-Foo", "hello")
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



=== TEST 6: response.clear_header() clears headers set via add_header
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.add_header("X-Foo", "hello")
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



=== TEST 7: response.clear_header() errors on non-supported phases
--- http_config
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local unsupported_phases = {
                "set",
                "rewrite",
                "content",
                "access",
                "log",
                "body_filter",
                "timer",
                "init_worker",
                "balancer",
                "ssl_cert",
                "ssl_session_store",
                "ssl_session_fetch",
            }

            for _, phase in ipairs(unsupported_phases) do
                ngx.get_phase = function()
                    return phase
                end

                local ok, err = pcall(sdk.response.clear_header, "test")
                if not ok then
                    ngx.say(err)
                end
            end
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body
kong.response.clear_header is disabled in the context of set
kong.response.clear_header is disabled in the context of rewrite
kong.response.clear_header is disabled in the context of content
kong.response.clear_header is disabled in the context of access
kong.response.clear_header is disabled in the context of log
kong.response.clear_header is disabled in the context of body_filter
kong.response.clear_header is disabled in the context of timer
kong.response.clear_header is disabled in the context of init_worker
kong.response.clear_header is disabled in the context of balancer
kong.response.clear_header is disabled in the context of ssl_cert
kong.response.clear_header is disabled in the context of ssl_session_store
kong.response.clear_header is disabled in the context of ssl_session_fetch
--- no_error_log
[error]
