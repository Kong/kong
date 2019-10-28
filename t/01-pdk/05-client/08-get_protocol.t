use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use Test::Nginx::Socket::Lua::Stream;
use t::Util;

$ENV{TEST_NGINX_CERT_DIR} ||= File::Spec->catdir(server_root(), '..', 'certs');
$ENV{TEST_NGINX_NXSOCK}   ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: client.get_protocol() returns the protocol on single-protocol matched route
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            ngx.ctx.route = {
              protocols = { "https" }
            }

            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            ngx.say("protocol=", assert(pdk.client.get_protocol()))
        }
    }
--- request
GET /t
--- response_body
protocol=https
--- no_error_log
[error]



=== TEST 2: client.get_protocol() returns "http" when subsystem is "http"
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            ngx.ctx.route = {
              protocols = { "http", "https" }
            }

            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            ngx.say("protocol=", assert(pdk.client.get_protocol()))
        }
    }
--- request
GET /t
--- response_body
protocol=http
--- no_error_log
[error]



=== TEST 3: client.get_protocol() returns "https" when kong receives an https request
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock ssl;
        ssl_certificate $ENV{TEST_NGINX_CERT_DIR}/test.crt;
        ssl_certificate_key $ENV{TEST_NGINX_CERT_DIR}/test.key;

        location / {
            content_by_lua_block {
                ngx.ctx.route = {
                  protocols = { "http", "https" }
                }

                local PDK = require "kong.pdk"
                local pdk = PDK.new()
                ngx.say("protocol=", assert(pdk.client.get_protocol()))
            }
        }
    }
}
--- config
    location = /t {
        proxy_ssl_verify off;
        proxy_pass https://unix:$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
protocol=https
--- no_error_log
[error]



=== TEST 4: client.get_protocol() returns "https" when kong receives an http request from a trusted ip and allow_terminated is true
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            ngx.ctx.route = {
              protocols = { "http", "https" }
            }

            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            pdk.ip.is_trusted = function() return true end -- mock
            ngx.say("protocol=", assert(pdk.client.get_protocol(true)))
        }
    }
--- request
GET /t
--- more_headers
X-Forwarded-Proto: https
--- response_body
protocol=https
--- no_error_log
[error]



=== TEST 5: client.get_protocol() returns "http" when kong receives an http request but allow_terminated is false
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            ngx.ctx.route = {
              protocols = { "http", "https" }
            }

            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            pdk.ip.is_trusted = function() return true end -- mock
            ngx.say("protocol=", assert(pdk.client.get_protocol(false))) -- was true
        }
    }
--- request
GET /t
--- more_headers
X-Forwarded-Proto: https
--- response_body
protocol=http
--- no_error_log
[error]



=== TEST 6: client.get_protocol() returns "http" when kong receives an http request from a non trusted ip

--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            ngx.ctx.route = {
              protocols = { "http", "https" }
            }

            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            pdk.ip.is_trusted = function() return false end -- mock, was true
            ngx.say("protocol=", assert(pdk.client.get_protocol(true)))
        }
    }
--- request
GET /t
--- more_headers
X-Forwarded-Proto: https
--- response_body
protocol=http
--- no_error_log
[error]



=== TEST 7: client.get_protocol() returns "http" when kong receives an http request with a non-https x-forwarded-proto header

--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            ngx.ctx.route = {
              protocols = { "http", "https" }
            }

            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            pdk.ip.is_trusted = function() return true end -- mock
            ngx.say("protocol=", assert(pdk.client.get_protocol(true)))
        }
    }
--- request
GET /t
--- more_headers
X-Forwarded-Proto: something other than "https"
--- response_body
protocol=http
--- no_error_log
[error]



=== TEST 8: client.get_protocol() returns "http" when the request has no x-forwarded-proto header
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            ngx.ctx.route = {
              protocols = { "http", "https" }
            }

            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            pdk.ip.is_trusted = function() return true end -- mock
            ngx.say("protocol=", assert(pdk.client.get_protocol(true)))
        }
    }
--- request
GET /t
--- response_body
protocol=http
--- no_error_log
[error]



=== TEST 9: client.get_protocol() returns "tcp" on tcp connections
--- stream_config eval
qq{
    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock proxy_protocol;
        content_by_lua_block {
            ngx.ctx.route = {
              protocols = { "tcp", "tls" }
            }

            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            ngx.say("protocol=", assert(pdk.client.get_protocol()))
        }
    }
}
--- stream_server_config
    content_by_lua_block {
        local sock = ngx.socket.tcp()
        sock:connect("unix:$TEST_NGINX_NXSOCK/nginx.sock")
        local request = "PROXY TCP4 10.0.0.1 " ..
                        ngx.var.server_addr    .. " " ..
                        ngx.var.remote_port    .. " " ..
                        ngx.var.server_port    .. "\r\n"
        sock:send(request)
        ngx.print(sock:receive())
    }
--- stream_response chop
protocol=tcp
--- no_error_log
[error]



=== TEST 10: client.get_protocol() returns "tls" on tls connections
--- stream_config eval
qq{
    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock proxy_protocol;

        content_by_lua_block {
            kong = {
              configuration = {},
            }

            ngx.ctx.route = {
              protocols = { "tcp", "tls" }
            }

            ngx.ctx.balancer_data = {
              scheme = "tls",
              ssl_ctx = {},
            }

            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            ngx.say("protocol=", assert(pdk.client.get_protocol()))
        }
    }
}
--- stream_server_config
    content_by_lua_block {
        local sock = ngx.socket.tcp()
        sock:connect("unix:$TEST_NGINX_NXSOCK/nginx.sock")
        local request = "PROXY TCP4 10.0.0.1 " ..
                        ngx.var.server_addr    .. " " ..
                        ngx.var.remote_port    .. " " ..
                        ngx.var.server_port    .. "\r\n"
        sock:send(request)
        ngx.print(sock:receive())
    }
--- stream_response chop
protocol=tls
--- no_error_log
[error]
