use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3) + 1;

run_tests();

__DATA__

=== TEST 1: response.set_headers() errors if arguments are not given
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local ok, err = pcall(pdk.response.set_headers)
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
headers must be a table
--- no_error_log
[error]



=== TEST 2: response.set_headers() errors if headers is not a table
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local ok, err = pcall(pdk.response.set_headers, 127001)
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
headers must be a table
--- no_error_log
[error]



=== TEST 3: response.set_headers() sets a header in the downstream response
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
            }

            header_filter_by_lua_block {
                local PDK = require "kong.pdk"
                local pdk = PDK.new()

                pdk.response.set_headers({["X-Foo"] = "hello world"})
            }
        }
    }
}
--- config
    location = /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;

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
X-Foo: {hello world}
--- no_error_log
[error]



=== TEST 4: response.set_headers() replaces all headers with that name if any exist
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.header["X-Foo"] = { "bla bla", "baz" }
            }
        }
    }
}
--- config
    location = /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.set_headers({["X-Foo"] = "hello world"})
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
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
            }

            header_filter_by_lua_block {
                local PDK = require "kong.pdk"
                local pdk = PDK.new()

                pdk.response.set_headers({["X-Foo"] = ""})
            }
        }
    }
}
--- config
    location = /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;

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
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
            }

            header_filter_by_lua_block {
                local PDK = require "kong.pdk"
                local pdk = PDK.new()

                pdk.response.set_headers({["X-Foo"] = "     hello"})
            }
        }
    }
}
--- config
    location = /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;

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
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
            }

            header_filter_by_lua_block {
                local PDK = require "kong.pdk"
                local pdk = PDK.new()

                pdk.response.set_headers({["X-Foo"] = "hello     "})
            }
        }
    }
}
--- config
    location = /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;

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
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
            }

            header_filter_by_lua_block {
                local PDK = require "kong.pdk"
                local pdk = PDK.new()

                pdk.response.set_headers({["X-Foo"] = ""})
            }
        }
    }
}
--- config
    location = /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;

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
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            local ok, err = pcall(pdk.response.set_headers, {[2] = "foo"})
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
invalid header name "2": got number, expected string
--- no_error_log
[error]



=== TEST 10: response.set_headers() errors if value is of a bad type
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local ok, err = pcall(pdk.response.set_headers, {["foo"] = function() end})
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
invalid header value for "foo": got function, expected string, number, boolean or array of strings
--- no_error_log
[error]



=== TEST 11: response.set_headers() errors if array element is of a bad type
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local ok, err = pcall(pdk.response.set_headers, {["foo"] = {{}}})
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
invalid header value in array "foo": got table, expected string
--- no_error_log
[error]



=== TEST 12: response.set_headers() errors if array element is number
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local ok, err = pcall(pdk.response.set_headers, {["foo"] = {123}})
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
invalid header value in array "foo": got number, expected string
--- no_error_log
[error]



=== TEST 13: response.set_headers() ignores non-sequence elements in arrays
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
            }

            header_filter_by_lua_block {
                local PDK = require "kong.pdk"
                local pdk = PDK.new()

                pdk.response.set_headers({
                    ["X-Foo"] = {
                        "hello",
                        "world",
                        ["foo"] = "bar",
                    }
                })
            }
        }
    }
}
--- config
    location = /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;

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



=== TEST 14: response.set_headers() removes headers when given an empty array
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.header["X-Foo"] = { "hello", "world" }

            }
        }
    }
}
--- config
    location = /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.set_headers({
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



=== TEST 15: response.set_headers() replaces every header of a given name
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.header["X-Foo"] = { "aaa", "bbb", "ccc", "ddd", "eee" }

            }
        }
    }
}
--- config
    location = /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.set_headers({
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



=== TEST 16: response.set_headers() accepts an empty table
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local ok, err pdk.response.set_headers({})
            if not ok then
                ngx.ctx.err = err
            end
        }

        body_filter_by_lua_block {
            ngx.arg[1] = ngx.ctx.err or "ok"
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
ok
--- no_error_log
[error]



=== TEST 17: response.set_headers() does not error in header_filter even if headers have already been sent
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            ngx.send_headers()
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local ok, err = pcall(pdk.response.set_headers, { ["Content-Type"] = "text/plain" })
            if not ok then
                ngx.ctx.err = err

            else
                ngx.ctx.err = "ok"
            end
        }

        body_filter_by_lua_block {
            ngx.arg[1] = ngx.ctx.err
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_headers_like
Content-Type: text/plain
--- response_body chop
ok
--- no_error_log
[error]
