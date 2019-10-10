use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use Test::Nginx::Socket::Lua::Stream;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: nginx.get_subsystem() returns http on regular http requests
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local subsystem = pdk.nginx.get_subsystem()

            ngx.say("subsystem=", subsystem)
        }
    }
--- request
GET /t
--- response_body
subsystem=http
--- no_error_log
[error]



=== TEST 2: returns http on error-handling requests from http
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        server_name kong;
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        error_page 400 /error_handler;

        location = /error_handler {
          internal;

          content_by_lua_block {
              local PDK = require "kong.pdk"
              local pdk = PDK.new()
              local subsystem = pdk.nginx.get_subsystem()
              local msg = "subsystem=" .. subsystem
              -- must change the status to 200, otherwise nginx will
              -- use the default 400 error page for the body
              return pdk.response.exit(200, msg)
          }
        }

        location / {
          content_by_lua_block {
            error("This should never be reached on this test")
          }
        }
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()
            sock:connect("unix:$TEST_NGINX_NXSOCK/nginx.sock")
            sock:send("invalid http request")
            ngx.print(sock:receive("*a"))
        }
    }

--- request
GET /t
--- response_body_like chop
HTTP.*? 200 OK(\s|.)+subsystem=http
--- no_error_log
[error]



=== TEST 3: nginx.get_subsystem() returns "stream" on tcp connections
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
            ngx.say("subsystem=", assert(pdk.nginx.get_subsystem()))
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
subsystem=stream
--- no_error_log
[error]
