use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use File::Spec;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: client.get_port() returns client port
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("port: ", sdk.client.get_port())
        }
    }
--- request
GET /t
--- response_body_like chomp
port: \d+
--- no_error_log
[error]



=== TEST 2: client.get_port() returns a number
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.say("port type: ", type(sdk.client.get_port()))
        }
    }
--- request
GET /t
--- response_body
port type: number
--- no_error_log
[error]



=== TEST 3: client.get_ip() returns client port not affected by proxy_protocol
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock proxy_protocol;

        location / {
            real_ip_header proxy_protocol;

            set_real_ip_from 0.0.0.0/0;
            set_real_ip_from ::/0;
            set_real_ip_from unix:;

            content_by_lua_block {
                local SDK = require "kong.sdk"
                local sdk = SDK.new()

                ngx.say("port: ", sdk.client.get_port())
            }
        }
    }
--- config
    location = /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()
            sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")

            local request = "PROXY TCP4 10.0.0.1 " ..
                            ngx.var.server_addr    .. " " ..
                            ngx.var.remote_port    .. " " ..
                            ngx.var.server_port    .. "\r\n" ..
                            "GET /\r\n"

            sock:send(request)
            ngx.print(sock:receive "*a")
        }
    }
--- request
GET /t
--- response_body
port: nil
--- no_error_log
[error]
