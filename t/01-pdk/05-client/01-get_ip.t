use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use Test::Nginx::Socket::Lua::Stream;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: client.get_ip() returns client ip
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        real_ip_header X-Real-IP;

        set_real_ip_from 0.0.0.0/0;
        set_real_ip_from ::/0;
        set_real_ip_from unix:;

        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("ip: ", pdk.client.get_ip())
        }
    }
--- request
GET /t
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
ip: 127.0.0.1
--- no_error_log
[error]



=== TEST 2: client.get_ip() returns client ip (stream)
--- stream_server_config
    set_real_ip_from 0.0.0.0/0;
    set_real_ip_from ::/0;
    set_real_ip_from unix:;

    content_by_lua_block {
        local PDK = require "kong.pdk"
        local pdk = PDK.new()

        ngx.say("ip: ", pdk.client.get_ip())
    }
--- stream_response
ip: 127.0.0.1
--- no_error_log
[error]



=== TEST 3: client.get_ip() returns client ip not affected by proxy_protocol
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        server_name kong;
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock proxy_protocol;

        location / {
            real_ip_header proxy_protocol;

            set_real_ip_from 0.0.0.0/0;
            set_real_ip_from ::/0;
            set_real_ip_from unix:;

            content_by_lua_block {
                local PDK = require "kong.pdk"
                local pdk = PDK.new()

                ngx.say("ip: ", pdk.client.get_ip())
            }
        }
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()
            sock:connect("unix:$TEST_NGINX_NXSOCK/nginx.sock")

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
ip: unix:
--- no_error_log
[error]



=== TEST 4: client.get_ip() returns client ip not affected by proxy_protocol (stream)
--- stream_config eval
qq{
    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock proxy_protocol;

        set_real_ip_from 0.0.0.0/0;
        set_real_ip_from ::/0;
        set_real_ip_from unix:;

        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("ip: ", pdk.client.get_ip())
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
                        ngx.var.server_port    .. "\r\n" ..
                        "Hello!\r\n"

        sock:send(request)
        ngx.print(sock:receive())
    }
--- stream_response chop
ip: unix:
--- no_error_log
[error]
