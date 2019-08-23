use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use Test::Nginx::Socket::Lua::Stream;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: client.get_forwarded_port() returns forwarded client port
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            --pdk.init(nil, "ip")

            ngx.say("port: ", pdk.client.get_forwarded_port())
        }
    }
--- request
GET /t
--- response_body_like chomp
port: \d+
--- no_error_log
[error]



=== TEST 2: client.get_forwarded_port() returns a number
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            --pdk.init(nil, "ip")

            ngx.say("port type: ", type(pdk.client.get_forwarded_port()))
        }
    }
--- request
GET /t
--- response_body
port type: number
--- no_error_log
[error]



=== TEST 3: client.get_forwarded_port() returns client port with X-Real-IP header when trusted
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

            ngx.say("port: ", pdk.client.get_forwarded_port())
        }
    }
--- request
GET /t
--- more_headers
X-Real-IP: 10.0.0.1:1234
--- response_body
port: 1234
--- no_error_log
[error]



=== TEST 4: client.get_forwarded_port() returns nil as client port when X-Real-IP doesn't define port when trusted
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

            ngx.say("port: ", pdk.client.get_forwarded_port())
        }
    }
--- request
GET /t
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
port: nil
--- no_error_log
[error]



=== TEST 5: client.get_forwarded_port() returns client port with X-Forwarded-For header when trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        real_ip_header X-Forwarded-For;

        set_real_ip_from 0.0.0.0/0;
        set_real_ip_from ::/0;
        set_real_ip_from unix:;

        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("port: ", pdk.client.get_forwarded_port())
        }
    }
--- request
GET /t
--- more_headers
X-Forwarded-For: 10.0.0.1:1234
--- response_body
port: 1234
--- no_error_log
[error]



=== TEST 6: client.get_forwarded_port() returns nil as client port when X-Forwarded-For doesn't define port when trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        real_ip_header X-Forwarded-For;

        set_real_ip_from 0.0.0.0/0;
        set_real_ip_from ::/0;
        set_real_ip_from unix:;

        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("port: ", pdk.client.get_forwarded_port())
        }
    }
--- request
GET /t
--- more_headers
X-Forwarded-For: 10.0.0.1
--- response_body
port: nil
--- no_error_log
[error]



=== TEST 7: client.get_forwarded_port() returns client port with proxy_protocol when trusted
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

                ngx.say("port: ", pdk.client.get_forwarded_port())
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
                            1234                   .. " " ..
                            ngx.var.server_port    .. "\r\n" ..
                            "GET /\r\n"

            sock:send(request)
            ngx.print(sock:receive "*a")
        }
    }
--- request
GET /t
--- response_body
port: 1234
--- no_error_log
[error]



=== TEST 8: client.get_forwarded_port() returns client port with proxy_protocol when trusted (stream)
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

            ngx.say("port: ", pdk.client.get_forwarded_port())
        }
    }
}
--- stream_server_config
    content_by_lua_block {
        local sock = ngx.socket.tcp()
        sock:connect("unix:$TEST_NGINX_NXSOCK/nginx.sock")

        local request = "PROXY TCP4 10.0.0.1 " ..
                        ngx.var.server_addr    .. " " ..
                        1234                   .. " " ..
                        ngx.var.server_port    .. "\r\n" ..
                        "Hello!\r\n"

        sock:send(request)
        ngx.print(sock:receive())
    }
--- stream_response chop
port: 1234
--- no_error_log
[error]



=== TEST 9: client.get_forwarded_port() returns client port from last hop with X-Real-IP not having port when not trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        real_ip_header X-Real-IP;

        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("port: ", pdk.client.get_forwarded_port())
        }
    }
--- request
GET /t
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body_like
port: \d+
--- no_error_log
[error]



=== TEST 10: client.get_forwarded_port() returns client port from last hop with X-Forwarded-For not having port when not trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        real_ip_header X-Forwarded-For;

        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("port: ", pdk.client.get_forwarded_port())
        }
    }
--- request
GET /t
--- more_headers
X-Forwarded-For: 10.0.0.1
--- response_body_like
port: \d+
--- no_error_log
[error]



=== TEST 11: client.get_forwarded_port() returns client port from last hop with X-Real-IP with port when not trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        real_ip_header X-Forwarded-For;

        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("port: ", pdk.client.get_forwarded_port())
        }
    }
--- request
GET /t
--- more_headers
X-Real-IP: 10.0.0.1:1234
--- response_body_unlike
port: 1234
--- response_body_like
port: \d+
--- no_error_log
[error]



=== TEST 12: client.get_forwarded_port() returns client port from last hop with X-Forwarded-For with port when not trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        real_ip_header X-Forwarded-For;

        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("port: ", pdk.client.get_forwarded_port())
        }
    }
--- request
GET /t
--- more_headers
X-Forwarded-For: 10.0.0.1:1234
--- response_body_unlike
port: 1234
--- response_body_like
port: \d+
--- no_error_log
[error]



=== TEST 13: client.get_forwarded_port() returns client port from last hop with proxy_protocol when not trusted
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        server_name kong;
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock proxy_protocol;

        location / {
            real_ip_header proxy_protocol;

            content_by_lua_block {
                local PDK = require "kong.pdk"
                local pdk = PDK.new()

                ngx.say("port: ", pdk.client.get_forwarded_port())
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
                            1234                   .. " " ..
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



=== TEST 14: client.get_forwarded_port() returns client port from last hop with proxy_protocol when not trusted (stream)
--- stream_config eval
qq{
    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock proxy_protocol;

        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("port: ", pdk.client.get_forwarded_port())
        }
    }
}
--- stream_server_config
    content_by_lua_block {
        local sock = ngx.socket.tcp()
        sock:connect("unix:$TEST_NGINX_NXSOCK/nginx.sock")

        local request = "PROXY TCP4 10.0.0.1 " ..
                        ngx.var.server_addr    .. " " ..
                        1234                   .. " " ..
                        ngx.var.server_port    .. "\r\n" ..
                        "Hello!\r\n"

        sock:send(request)
        ngx.print(sock:receive())
    }
--- stream_response chop
port: nil
--- no_error_log
[error]
