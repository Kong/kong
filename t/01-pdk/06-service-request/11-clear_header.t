use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: service.request.clear_header() errors if arguments are not given
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.request.clear_header)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
header must be a string
--- no_error_log
[error]



=== TEST 2: service.request.clear_header() errors if header is not a string
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.request.clear_header, 127001, "foo")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
header must be a string
--- no_error_log
[error]



=== TEST 3: service.request.clear_header() clears a given header
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: {" .. tostring(ngx.req.get_headers()["X-Foo"]) .. "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.clear_header("X-Foo")

        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- more_headers
X-Foo: bar
--- response_body
X-Foo: {nil}
--- no_error_log
[error]



=== TEST 4: service.request.clear_header() clears multiple given headers
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: {" .. tostring(ngx.req.get_headers()["X-Foo"]) .. "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.clear_header("X-Foo")

        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- more_headers
X-Foo: hello
X-Foo: world
--- response_body
X-Foo: {nil}
--- no_error_log
[error]



=== TEST 5: service.request.clear_header() clears headers set via set_header
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: {" .. tostring(ngx.req.get_headers()["X-Foo"]) .. "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_header("X-Foo", "hello")

            pdk.service.request.clear_header("X-Foo")

        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
X-Foo: {nil}
--- no_error_log
[error]



=== TEST 6: service.request.clear_header() clears headers set via add_header
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: {" .. tostring(ngx.req.get_headers()["X-Foo"]) .. "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_header("X-Foo", "hello")

            pdk.service.request.add_header("X-Foo", "world")

            pdk.service.request.clear_header("X-Foo")

        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
X-Foo: {nil}
--- no_error_log
[error]
