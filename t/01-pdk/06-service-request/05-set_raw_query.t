use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: service.request.set_raw_query() errors if not a string
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.request.set_raw_query, 127001)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
query must be a string
--- no_error_log
[error]



=== TEST 2: service.request.set_raw_query() errors if given no arguments
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.request.set_raw_query)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
query must be a string
--- no_error_log
[error]



=== TEST 3: service.request.set_raw_query() accepts an empty string
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        server_name K0nG;
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("query: {", tostring(ngx.var.args), "}")
            }
        }
    }
}
--- config
    location = /t {

        set $upstream_host '';

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_raw_query("")
        }

        proxy_set_header Host $upstream_host;
        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
query: {nil}
--- no_error_log
[error]



=== TEST 4: service.request.set_raw_query() sets the query string
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        server_name K0nG;
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("query: {", tostring(ngx.var.args), "}")
            }
        }
    }
}
--- config
    location = /t {

        set $upstream_host '';

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_raw_query("foo=bar&bla&baz=hello%20world")
        }

        proxy_set_header Host $upstream_host;
        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
query: {foo=bar&bla&baz=hello%20world}
--- no_error_log
[error]



=== TEST 5: service.request.set_raw_query() replaces any existing query string
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        server_name K0nG;
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("query: {", tostring(ngx.var.args), "}")
            }
        }
    }
}
--- config
    location = /t {

        set $upstream_host '';

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_raw_query("foo=bar&bla&baz=hello%20world")
        }

        proxy_set_header Host $upstream_host;
        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t?bla&baz=hello%20mars&something_else=is_set
--- response_body
query: {foo=bar&bla&baz=hello%20world}
--- no_error_log
[error]
