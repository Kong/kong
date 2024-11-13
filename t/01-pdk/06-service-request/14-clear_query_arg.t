use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
do "./t/Util.pm";

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: service.request.clear_query_arg() errors if arguments are not given
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.request.clear_query_arg)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
query argument name must be a string
--- no_error_log
[error]



=== TEST 2: service.request.clear_query_arg() errors if query argument name is not a string
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.request.clear_query_arg, 127001)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
query argument name must be a string
--- no_error_log
[error]



=== TEST 3: service.request.clear_query_arg() clears a given query argument
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("foo: {" .. tostring(ngx.req.get_uri_args()["foo"]) .. "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.clear_query_arg("foo")
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t?foo=bar
--- response_body
foo: {nil}
--- no_error_log
[error]



=== TEST 4: service.request.clear_query_arg() clears multiple given query arguments
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("foo: {" .. tostring(ngx.req.get_uri_args()["foo"]) .. "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.clear_query_arg("foo")
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t?foo=bar&foo=baz
--- response_body
foo: {nil}
--- no_error_log
[error]



=== TEST 5: service.request.clear_query_arg() clears query arguments set via set_query
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("foo: {" .. tostring(ngx.req.get_uri_args()["foo"]) .. "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_query({ foo = "bar" })
            pdk.service.request.clear_query_arg("foo")
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
foo: {nil}
--- no_error_log
[error]



=== TEST 6: service.request.clear_query_arg() clears query arguments set via set_raw_query
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("foo: {" .. tostring(ngx.req.get_uri_args()["foo"]) .. "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_raw_query("foo=bar")
            pdk.service.request.clear_query_arg("foo")
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
foo: {nil}
--- no_error_log
[error]



=== TEST 7: service.request.clear_query_arg() retains the order of query arguments
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("query: " .. tostring(ngx.var.args))
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.clear_query_arg("a")
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t?a=0&d=1&a=2&c=3&a=4&b=5&a=6&d=7&a=8
--- response_body
query: d=1&c=3&b=5&d=7
--- no_error_log
[error]
