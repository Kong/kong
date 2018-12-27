use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_path_with_query() returns the path if no querystring
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local path_and_querystring = pdk.request.get_path_with_query()

            ngx.say("path_and_querystring=", path_and_querystring)
        }
    }
--- request
GET /t
--- response_body
path_and_querystring=/t
--- no_error_log
[error]



=== TEST 2: request.get_path_with_query() returns path + ? + querystring
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local path_and_querystring = pdk.request.get_path_with_query()

            ngx.say("path_and_querystring=", path_and_querystring)
        }
    }
--- request
GET /t?foo=1&bar=2
--- response_body
path_and_querystring=/t?foo=1&bar=2
--- no_error_log
[error]



=== TEST 3: returns empty string on error-handling requests
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
              local path = pdk.request.get_path_with_query()
              local msg = "get_path_with_query: '" .. path .. "', type: " .. type(path)
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
HTTP.*? 200 OK(\s|.)+get_path_with_query: '', type: string
--- no_error_log
[error]
