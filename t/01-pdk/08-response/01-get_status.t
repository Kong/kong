use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: response.get_status() returns a number
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.ctx.type = "type: " .. type(pdk.response.get_status())
        }

        body_filter_by_lua_block {
            ngx.arg[1] = ngx.ctx.type
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
type: number
--- no_error_log
[error]



=== TEST 2: response.get_status() returns 200 from service
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location / {
            return 200;
        }
    }
}
--- config
    location /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil
        }

        body_filter_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.arg[1] = "status: " .. pdk.response.get_status()
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
status: 200
--- no_error_log
[error]



=== TEST 3: response.get_status() returns 404 from service
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location / {
            return 404;
        }
    }
}
--- config
    location /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil
        }

        body_filter_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.arg[1] = "status: " .. pdk.response.get_status()
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- error_code: 404
--- response_body chop
status: 404
--- no_error_log
[error]



=== TEST 4: response.get_status() returns last status code set
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location / {
            content_by_lua_block {
                ngx.status = 203
            }
        }
    }
}
--- config
    location /t {
        rewrite_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.status = 201
        }

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.status = 202
        }

        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            assert(pdk.response.get_status() == 203, "203 ~=" .. tostring(pdk.response.get_status()))
            ngx.status = 204
            assert(pdk.response.get_status() == 204, "204 ~=" .. tostring(pdk.response.get_status()))
        }

        body_filter_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            assert(pdk.response.get_status() == 204, "204 ~=" .. tostring(pdk.response.get_status()))
        }

        log_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            assert(pdk.response.get_status() == 204, "204 ~=" .. tostring(pdk.response.get_status()))
        }
    }
--- request
GET /t
--- error_code: 204
--- response_body chop
--- no_error_log
[error]
