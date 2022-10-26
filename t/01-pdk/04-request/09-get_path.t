use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
do "./t/Util.pm";

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_path() returns path component of uri
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("normalized path: ", pdk.request.get_path())
        }
    }
--- request
GET /t
--- response_body
normalized path: /t
--- no_error_log
[error]



=== TEST 2: request.get_path() returns at least slash
--- http_config eval: $t::Util::HttpConfig
--- config
    location = / {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("normalized path: ", pdk.request.get_path())
        }
    }
--- request
GET http://kong
--- response_body
normalized path: /
--- no_error_log
[error]



=== TEST 3: request.get_path() is normalized
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t/ {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("normalized path: ", pdk.request.get_path())
        }
    }
--- request
GET /t/Abc%20123%C3%B8/parent/../test/.
--- response_body
normalized path: /t/Abc 123ø/test/
--- no_error_log
[error]



=== TEST 4: request.get_path() strips query string
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t/ {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("normalized path: ", pdk.request.get_path())
        }
    }
--- request
GET /t/demo?param=value
--- response_body
normalized path: /t/demo
--- no_error_log
[error]
