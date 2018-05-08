use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: response.set_headers() errors if arguments are not given
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.response.set_headers)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
headers must be a table
--- no_error_log
[error]



=== TEST 2: response.set_headers() errors if headers is not a table
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.response.set_headers, 127001)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
headers must be a table
--- no_error_log
[error]



=== TEST 3: response.set_headers() sets a header in the downstream response
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                local SDK = require "kong.sdk"
                local sdk = SDK.new()

                sdk.response.set_headers({["X-Foo"] = "hello world"})
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
            ngx.arg[1] = "X-Foo: {" .. ngx.resp.get_headers()["X-Foo"] .. "}"
        }
    }
--- request
GET /t
--- response_body chop
X-Foo: {hello world}
--- no_error_log
[error]



=== TEST 4: response.set_headers() replaces all headers with that name if any exist
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

            sdk.response.set_headers({["X-Foo"] = "hello world"})
        }

        body_filter_by_lua_block {
            ngx.arg[1] = "X-Foo: {" .. ngx.resp.get_headers()["X-Foo"] .. "}"
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
X-Foo: {hello world}
--- no_error_log
[error]



=== TEST 5: response.set_headers() can set to an empty string
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                local SDK = require "kong.sdk"
                local sdk = SDK.new()

                sdk.response.set_headers({["X-Foo"] = ""})
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
            ngx.arg[1] = "X-Foo: {" .. ngx.resp.get_headers()["X-Foo"] .. "}"
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
X-Foo: {}
--- no_error_log
[error]



=== TEST 6: response.set_headers() ignores spaces in the beginning of value
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                local SDK = require "kong.sdk"
                local sdk = SDK.new()

                sdk.response.set_headers({["X-Foo"] = "     hello"})
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
            ngx.arg[1] = "X-Foo: {" .. ngx.resp.get_headers()["X-Foo"] .. "}"
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
X-Foo: {hello}
--- no_error_log
[error]



=== TEST 7: response.set_headers() ignores spaces in the end of value
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                local SDK = require "kong.sdk"
                local sdk = SDK.new()

                sdk.response.set_headers({["X-Foo"] = "hello     "})
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
            ngx.arg[1] = "X-Foo: {" .. ngx.resp.get_headers()["X-Foo"] .. "}"
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
X-Foo: {hello}
--- no_error_log
[error]



=== TEST 8: response.set_headers() can differentiate empty string from unset
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                local SDK = require "kong.sdk"
                local sdk = SDK.new()

                sdk.response.set_headers({["X-Foo"] = ""})
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
            local headers = ngx.resp.get_headers()
            ngx.arg[1] = "X-Foo: {" .. headers["X-Foo"] .. "}\n" ..
                         "X-Bar: {" .. tostring(headers["X-Bar"]) .. "}"
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
X-Foo: {}
X-Bar: {nil}
--- no_error_log
[error]



=== TEST 9: response.set_headers() errors if name is not a string
--- http_config
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.response.set_headers, {[2] = "foo"})
            assert(not pok)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
invalid name "2": got number, expected string
--- no_error_log
[error]



=== TEST 10: response.set_headers() errors if value is of a bad type
--- http_config
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.response.set_headers, {["foo"] = 2})
            assert(not pok)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
invalid value in "foo": got number, expected string
--- no_error_log
[error]



=== TEST 11: response.set_headers() errors if array element is of a bad type
--- http_config
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.response.set_headers, {["foo"] = {2}})
            assert(not pok)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
invalid value in array "foo": got number, expected string
--- no_error_log
[error]



=== TEST 12: response.set_headers() ignores non-sequence elements in arrays
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                local SDK = require "kong.sdk"
                local sdk = SDK.new()

                sdk.response.set_headers({
                    ["X-Foo"] = {
                        "hello",
                        "world",
                        ["foo"] = "bar",
                    }
                })
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



=== TEST 13: response.set_headers() removes headers when given an empty array
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

            sdk.response.set_headers({
                ["X-Foo"] = {}
            })
        }

        body_filter_by_lua_block {
            local foo_headers = ngx.resp.get_headers()["X-Foo"] or {}
            local response = {}
            for i, v in ipairs(foo_headers) do
                response[i] = "X-Foo: {" .. tostring(v) .. "}"
            end

            table.insert(response, ":)")

            ngx.arg[1] = table.concat(response, "\n")
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
:)
--- no_error_log
[error]



=== TEST 14: response.set_headers() replaces every header of a given name
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.header["X-Foo"] = { "aaa", "bbb", "ccc", "ddd", "eee" }

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

            sdk.response.set_headers({
                ["X-Foo"] = { "xxx", "yyy", "zzz" }
            })
        }

        body_filter_by_lua_block {
            local foo_headers = ngx.resp.get_headers()["X-Foo"] or {}
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
X-Foo: {xxx}
X-Foo: {yyy}
X-Foo: {zzz}
--- no_error_log
[error]



=== TEST 15: response.set_headers() accepts an empty table
--- http_config
--- config
    location = /t {
        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.response.set_headers({})
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]



=== TEST 16: response.set_headers() errors if headers have already been sent
--- config
    location = /t {
        content_by_lua_block {
            ngx.send_headers()

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = pcall(sdk.response.set_headers, {})
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
