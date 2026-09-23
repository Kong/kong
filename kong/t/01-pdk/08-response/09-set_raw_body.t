use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
do "./t/Util.pm";

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: response.set_raw_body() errors if not a string
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }
        header_filter_by_lua_block {
            ngx.status = 200
            ngx.header["Content-Length"] = nil
        }
        body_filter_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.response.set_raw_body, 0)
            if not pok then
                pdk.response.set_raw_body(err .. "\n")
            end
        }
    }
--- request
GET /t
--- response_body
body must be a string
--- no_error_log
[error]



=== TEST 2: response.set_raw_body() errors if given no arguments
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }
        header_filter_by_lua_block {
            ngx.status = 200
            ngx.header["Content-Length"] = nil
        }
        body_filter_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.response.set_raw_body)
            if not pok then
                pdk.response.set_raw_body(err .. "\n")
            end
        }
    }
--- request
GET /t
--- response_body
body must be a string
--- no_error_log
[error]



=== TEST 3: response.set_raw_body() accepts an empty string
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            ngx.say("Default Content")
        }
        header_filter_by_lua_block {
            ngx.status = 200
            ngx.header["Content-Length"] = nil
        }
        body_filter_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.response.set_raw_body, "")
            if pok then
                ngx.arg[1] = "Empty Body:" .. (ngx.arg[1] or "")
            else
                ngx.arg[1] = "Error:" .. (err or "") .. "\n"
            end
        }
    }
--- request
GET /t
--- response_body
Empty Body:
--- no_error_log
[error]



=== TEST 4: response.set_raw_body() sets raw body
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }
        header_filter_by_lua_block {
            ngx.status = 200
            ngx.header["Content-Length"] = nil
        }
        body_filter_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.set_raw_body("Hello, World!\n")
        }
    }
--- request
GET /t
--- response_body
Hello, World!
--- no_error_log
[error]
