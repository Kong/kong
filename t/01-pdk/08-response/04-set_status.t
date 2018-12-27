use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: response.set_status() code must be a number
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local pdk = require "kong.pdk"
            local pdk = pdk.new()

            local ok, err = pcall(pdk.response.set_status)
            if not ok then
                ngx.ctx.err = err
            end
        }

        body_filter_by_lua_block {
            ngx.arg[1] = "error: " .. ngx.ctx.err
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
error: code must be a number
--- no_error_log
[error]



=== TEST 2: response.set_status() code must be a number between 100 and 599
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            ngx.header.content_length = nil

            local pdk = require "kong.pdk"
            local pdk = pdk.new()

            local ok1, err1 = pcall(pdk.response.set_status, 99)
            local ok2, err2 = pcall(pdk.response.set_status, 200)
            local ok3, err3 = pcall(pdk.response.set_status, 600)

            if not ok1 then
                ngx.ctx.err1 = err1
            end

            if ok2 then
                ngx.ctx.err2 = err2
            end

            if not ok3 then
                ngx.ctx.err3 = err3
            end
        }

        body_filter_by_lua_block {
            ngx.arg[1] = (ngx.ctx.err1 ~= nil and ngx.ctx.err1 or "ok") .. "\n" ..
                         (ngx.ctx.err2 ~= nil and ngx.ctx.err2 or "ok") .. "\n" ..
                         (ngx.ctx.err3 ~= nil and ngx.ctx.err3 or "ok")
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
code must be a number between 100 and 599
ok
code must be a number between 100 and 599
--- no_error_log
[error]



=== TEST 3: response.set_status() sets response status code
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
            }

            header_filter_by_lua_block {
                local pdk = require "kong.pdk"
                local pdk = pdk.new()

                pdk.response.set_status(204)
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
            ngx.arg[1] = "Status: " .. ngx.status
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- error_code: 204
--- response_body chop
Status: 204
--- no_error_log
[error]



=== TEST 4: response.set_status() replaces response status code
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
            }

            header_filter_by_lua_block {
                local pdk = require "kong.pdk"
                local pdk = pdk.new()

                pdk.response.set_status(204)
            }
        }
    }
}
--- config
    location = /t {
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;

        header_filter_by_lua_block {
            local pdk = require "kong.pdk"
            local pdk = pdk.new()

            pdk.response.set_status(200)
        }

        body_filter_by_lua_block {
            ngx.arg[1] = "Status: " .. ngx.status
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body chop
Status: 200
--- no_error_log
[error]
