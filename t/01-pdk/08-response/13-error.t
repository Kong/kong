use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 4);

run_tests();

__DATA__

=== TEST 1: service.response.error() use accept header
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            return pdk.response.error(502)
        }
    }

--- request
GET /t
--- more_headers
Accept: application/json
--- error_code: 502
--- response_headers_like
Content-Type: application/json; charset=utf-8
--- response_body chop
{
  "message":"An invalid response was received from the upstream server"
}
--- no_error_log
[error]



=== TEST 2: service.response.error() fallbacks to json
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            return pdk.response.error(400)
        }
    }

--- request
GET /t
--- error_code: 400
--- response_headers_like
Content-Type: application/json; charset=utf-8
--- response_body chop
{
  "message":"Bad request"
}
--- no_error_log
[error]



=== TEST 3: service.response.error() may ignore accept header
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            local headers = {
                ["Content-Type"] = "application/xml"
            }
            local msg = "this is fine"
            return pdk.response.error(503, msg, headers)
        }
    }

--- request
GET /t
--- more_headers
Accept: application/json
--- error_code: 503
--- response_headers_like
Content-Type: application/xml
--- response_body
<?xml version="1.0" encoding="UTF-8"?>
<error>
  <message>this is fine</message>
</error>
--- no_error_log
[error]



=== TEST 4: service.response.error() respects accept header priorities
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            return pdk.response.error(502)
        }
    }

--- request
GET /t
--- more_headers
Accept: text/plain;q=0.3, text/html;q=0.7, text/html;level=1, text/html;level=2;q=0.4, */*;q=0.5
--- error_code: 502
--- response_headers_like
Content-Type: text/html; charset=utf-8
--- response_body
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Kong Error</title>
  </head>
  <body>
    <h1>Kong Error</h1>
    <p>An invalid response was received from the upstream server.</p>
  </body>
</html>
--- no_error_log
[error]



=== TEST 5: service.response.error() has higher priority than handle_errors
--- http_config eval: $t::Util::HttpConfig
--- config
    error_page 500 502 /error_handler;
    location = /error_handler {
        internal;
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            return pdk.response.exit(200, "nothing happened")
        }
    }

    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            return pdk.response.error(500)
        }
    }

--- request
GET /t
--- error_code: 500
--- response_headers_like
Content-Type: application/json; charset=utf-8
--- response_body chop
{
  "message":"An unexpected error occurred"
}
--- no_error_log
[error]



=== TEST 6: service.response.error() formats default template
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            return pdk.response.error(419, "I'm not a teapot")
        }
    }

--- request
GET /t
--- more_headers
Accept: application/json
--- error_code: 419
--- response_headers_like
Content-Type: application/json; charset=utf-8
--- response_body chop
{
  "message":"I'm not a teapot"
}
--- no_error_log
[error]



=== TEST 7: service.response.error() overrides default message
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            return pdk.response.error(500, "oh no")
        }
    }

--- request
GET /t
--- more_headers
Accept: application/json
--- error_code: 500
--- response_headers_like
Content-Type: application/json; charset=utf-8
--- response_body chop
{
  "message":"oh no"
}
--- no_error_log
[error]



=== TEST 8: service.response.error() use accept header "*" mime sub-type
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            return pdk.response.error(410)
        }
    }

--- request
GET /t
--- more_headers
Accept: text/*
--- error_code: 410
--- response_headers_like
Content-Type: text/plain; charset=utf-8
--- response_body
Gone
--- no_error_log
[error]



=== TEST 9: response.error() maps http 400 to grpc InvalidArgument
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            ngx.req.http_version = function() return 2 end
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.error(400)
        }
    }
--- request
GET /t
--- more_headers
Content-Type: application/grpc
--- error_code: 400
--- response_headers_like
grpc-status: 3
grpc-message: InvalidArgument
--- no_error_log
[error]



=== TEST 10: response.error() maps http 401 to grpc Unauthenticated
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            ngx.req.http_version = function() return 2 end
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.error(401)
        }
    }
--- request
GET /t
--- more_headers
Content-Type: application/grpc
--- error_code: 401
--- response_headers_like
grpc-status: 16
grpc-message: Unauthenticated
--- no_error_log
[error]



=== TEST 11: response.error() maps http 403 to grpc PermissionDenied
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            ngx.req.http_version = function() return 2 end
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.error(403)
        }
    }
--- request
GET /t
--- more_headers
Content-Type: application/grpc
--- error_code: 403
--- response_headers_like
grpc-status: 7
grpc-message: PermissionDenied
--- no_error_log
[error]



=== TEST 12: response.error() maps http 429 to grpc ResourceExhausted
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        default_type 'text/test';
        access_by_lua_block {
            ngx.req.http_version = function() return 2 end
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.error(429)
        }
    }
--- request
GET /t
--- more_headers
Content-Type: application/grpc
--- error_code: 429
--- response_headers_like
grpc-status: 8
grpc-message: ResourceExhausted
--- no_error_log
[error]
