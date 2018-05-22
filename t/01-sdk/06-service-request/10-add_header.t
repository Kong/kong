use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: service.request.add_header() errors if arguments are not given
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.service.request.add_header)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
header must be a string
--- no_error_log
[error]



=== TEST 2: service.request.add_header() errors if header is not a string
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.service.request.add_header, 127001, "foo")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
header must be a string
--- no_error_log
[error]



=== TEST 3: service.request.add_header() errors if value is not a string
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.service.request.add_header, "foo", 123456)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
value must be a string
--- no_error_log
[error]



=== TEST 4: service.request.add_header() errors if value is not given
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.service.request.add_header, "foo")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
value must be a string
--- no_error_log
[error]



=== TEST 5: service.request.add_header("Host") sets ngx.ctx.balancer_address.host
--- config
    location = /t {

        set $upstream_host '';

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.ctx.balancer_address = {
                host = "foo.xyz"
            }

            local ok = sdk.service.request.add_header("Host", "example.com")

            ngx.say("host: ", ngx.ctx.balancer_address.host)
        }
    }
--- request
GET /t
--- response_body
host: example.com
--- no_error_log
[error]



=== TEST 6: service.request.add_header("host") has special Host-behavior in lowercase as well
--- config
    location = /t {

        set $upstream_host '';

        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.ctx.balancer_address = {
                host = "foo.xyz"
            }

            sdk.service.request.add_header("host", "example.com")

            ngx.say("host: ", ngx.ctx.balancer_address.host)
        }
    }
--- request
GET /t
--- response_body
host: example.com
--- no_error_log
[error]



=== TEST 7: service.request.add_header("Host") sets Host header sent to the service
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("host: ", ngx.req.get_headers()["Host"])
            }
        }
    }
--- config
    location = /t {

        set $upstream_host '';

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.ctx.balancer_address = {
                host = "foo.xyz"
            }

            sdk.service.request.add_header("Host", "example.com")

        }

        proxy_set_header Host $upstream_host;
        proxy_pass http://unix:/$TEST_NGINX_HTML_DIR/nginx.sock;
    }
--- request
GET /t
--- response_body
host: example.com
--- no_error_log
[error]



=== TEST 8: service.request.add_header("Host") cannot add two hosts
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("host: ", ngx.req.get_headers()["Host"])
            }
        }
    }
--- config
    location = /t {

        set $upstream_host '';

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.ctx.balancer_address = {
                host = "foo.xyz"
            }

            sdk.service.request.add_header("Host", "example.com")

            sdk.service.request.add_header("Host", "example2.com")

        }

        proxy_set_header Host $upstream_host;
        proxy_pass http://unix:/$TEST_NGINX_HTML_DIR/nginx.sock;
    }
--- request
GET /t
--- response_body
host: example2.com
--- no_error_log
[error]



=== TEST 9: service.request.add_header() sets a header in the request to the service
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: {" .. ngx.req.get_headers()["X-Foo"] .. "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.service.request.add_header("X-Foo", "hello world")

        }

        proxy_pass http://unix:/$TEST_NGINX_HTML_DIR/nginx.sock;
    }
--- request
GET /t
--- response_body
X-Foo: {hello world}
--- no_error_log
[error]



=== TEST 10: service.request.add_header() adds two headers to an request to the service
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                local foo_headers = ngx.req.get_headers()["X-Foo"]
                for _, v in ipairs(foo_headers) do
                    ngx.say("X-Foo: {" .. tostring(v) .. "}")
                end
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.service.request.add_header("X-Foo", "hello")

            sdk.service.request.add_header("X-Foo", "world")

        }

        proxy_pass http://unix:/$TEST_NGINX_HTML_DIR/nginx.sock;
    }
--- request
GET /t
--- response_body
X-Foo: {hello}
X-Foo: {world}
--- no_error_log
[error]



=== TEST 11: service.request.add_header() preserves headers with that name if any exist
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                local foo_headers = ngx.req.get_headers()["X-Foo"]
                for _, v in ipairs(foo_headers) do
                    ngx.say("X-Foo: {" .. tostring(v) .. "}")
                end
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.service.request.add_header("X-Foo", "hello world")

        }

        proxy_pass http://unix:/$TEST_NGINX_HTML_DIR/nginx.sock;
    }
--- request
GET /t
--- more_headers
X-Foo: bla bla
X-Foo: baz
--- response_body
X-Foo: {bla bla}
X-Foo: {baz}
X-Foo: {hello world}
--- no_error_log
[error]



=== TEST 12: service.request.add_header() can set to an empty string
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: {" .. ngx.req.get_headers()["X-Foo"] .. "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.service.request.add_header("X-Foo", "")

        }

        proxy_pass http://unix:/$TEST_NGINX_HTML_DIR/nginx.sock;
    }
--- request
GET /t
--- response_body
X-Foo: {}
--- no_error_log
[error]



=== TEST 13: service.request.add_header() ignores spaces in the beginning of value
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: {" .. ngx.req.get_headers()["X-Foo"] .. "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.service.request.add_header("X-Foo", "     hello")

        }

        proxy_pass http://unix:/$TEST_NGINX_HTML_DIR/nginx.sock;
    }
--- request
GET /t
--- response_body
X-Foo: {hello}
--- no_error_log
[error]



=== TEST 14: service.request.add_header() ignores spaces in the end of value
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: {" .. ngx.req.get_headers()["X-Foo"] .. "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.service.request.add_header("X-Foo", "hello       ")

        }

        proxy_pass http://unix:/$TEST_NGINX_HTML_DIR/nginx.sock;
    }
--- request
GET /t
--- response_body
X-Foo: {hello}
--- no_error_log
[error]



=== TEST 15: service.request.add_header() can differentiate empty string from unset
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location /t {
            content_by_lua_block {
                local headers = ngx.req.get_headers()
                ngx.say("X-Foo: {" .. headers["X-Foo"] .. "}")
                ngx.say("X-Bar: {" .. tostring(headers["X-Bar"]) .. "}")
            }
        }
    }
--- config
    location = /t {

        access_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            sdk.service.request.add_header("X-Foo", "")

        }

        proxy_pass http://unix:/$TEST_NGINX_HTML_DIR/nginx.sock;
    }
--- request
GET /t
--- response_body
X-Foo: {}
X-Bar: {nil}
--- no_error_log
[error]
