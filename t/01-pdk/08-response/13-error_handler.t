use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 4);

run_tests();

__DATA__

=== TEST 1: service.response.exit() returns template body
--- http_config eval: $t::Util::HttpConfig
--- config
    error_page 500 /error_handler;

    location = /error_handler {
        internal;

        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            return pdk.response.exit(200, "this is fine")
        }
    }

    location = /t {
        return 500;
    }

--- request
GET /t
--- error_code: 200
--- response_headers_like
Content-Type: text/plain
--- response_body chop
this is fine
--- no_error_log
[error]


=== TEST 2: service.response.error() ignores template body
--- http_config eval: $t::Util::HttpConfig
--- config
    error_page 500 /error_handler;

    location = /error_handler {
        internal;

        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            return pdk.response.exit(200, "this is not fine")
        }
    }

    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            return pdk.response.error(500, "this is fine")
        }
    }

--- request
GET /t
--- error_code: 500
--- response_headers_like
Content-Type: text/plain
--- response_body chop
this is fine
--- no_error_log
[error]


=== TEST 3: service.response.error() may ignore accept header
--- http_config eval: $t::Util::HttpConfig
--- config
    error_page 500 /error_handler;

    location = /error_handler {
        internal;

        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            return pdk.response.error(503,
                "<fine>this is</fine>",
                { ["Content-Type"] = "application/xml" }
            )
        }
    }

    location = /t {
        return 500;
    }

--- request
GET /t
--- more_headers
Accept: application/json
--- error_code: 503
--- response_headers_like
Content-Type: application/xml
--- response_body chop
<fine>this is</fine>
--- no_error_log
[error]
