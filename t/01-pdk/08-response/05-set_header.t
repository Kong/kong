use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
do "./t/Util.pm";

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: response.set_header() errors if arguments are not given
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local ok, err = pcall(pdk.response.set_header)
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
invalid header name "nil": got nil, expected string
--- no_error_log
[error]



=== TEST 2: response.set_header() errors if name is not a string
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local ok, err = pcall(pdk.response.set_header, 127001, "foo")
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
invalid header name "127001": got number, expected string
--- no_error_log
[error]



=== TEST 3: response.set_header() errors if value is not a table contain array of string 
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            local set_header = { {} }

            local ok, err = pcall(pdk.response.set_header, "foo", set_header)
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



=== TEST 4: response.set_header() errors if value is not given
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local _, err = pcall(pdk.response.set_header, "foo")
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
invalid header value for "foo": got nil, expected array of string, string, number or boolean
--- no_error_log
[error]



=== TEST 5: response.set_header() sets a header in the downstream response
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.set_header("X-Foo", "hello world")
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
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            ngx.header["X-Foo"] = { "First", "Second" }
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.set_header("X-Foo", "hello world")
        }

        body_filter_by_lua_block {
            local new_headers = ngx.resp.get_headers()

            ngx.arg[1] = "type: " ..  type(new_headers["X-Foo"])
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
type: string
--- no_error_log
[error]



=== TEST 7: response.set_header() can set to an empty string
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

                pdk.response.set_header("X-Foo", "")
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



=== TEST 8: response.set_header() does not set transfer-encoding
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        header_filter_by_lua_block {
            ngx.header.content_length = nil
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.set_header("Transfer-Encoding", "gzip")
            ngx.status = 200
        }

        body_filter_by_lua_block {
            local new_headers = ngx.resp.get_headers()

            ngx.arg[1] = "Transfer-Encoding: " ..  new_headers["Transfer-Encoding"]
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
Transfer-Encoding: chunked
--- error_log
manually setting Transfer-Encoding. Ignored.


=== TEST 8: response.set_header() with header table
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            local set_header = {"a", "b"}

            pdk.response.set_header("X-Foo", set_header)
        }

        body_filter_by_lua_block {
            local new_headers = ngx.resp.get_headers()

            local cjson = require("cjson")
            ngx.arg[1] = "X-Foo: {" ..  new_headers["X-Foo"][1] .. "," .. new_headers["X-Foo"][2] .. "}"

            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
X-Foo: {a,b}
--- no_error_log
[error]
