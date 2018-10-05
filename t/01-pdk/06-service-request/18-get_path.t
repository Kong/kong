use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: service.request.get_path() returns path component of uri
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        set $upstream_uri '/t';

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("path: ", pdk.service.request.get_path())
        }
    }
--- request
GET /t
--- response_body
path: /t
--- no_error_log
[error]



=== TEST 2: service.request.get_path() is not normalized
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        set $upstream_uri '/t/Abc%20123%C3%B8/../test/.';

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("path: ", pdk.service.request.get_path())
        }
    }
--- request
GET /t
--- response_body
path: /t/Abc%20123%C3%B8/../test/.
--- no_error_log
[error]



=== TEST 3: service.request.get_path() strips query string
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        set $upstream_uri '/t/demo?param=value';

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("path: ", pdk.service.request.get_path())
        }
    }
--- request
GET /t
--- response_body
path: /t/demo
--- no_error_log
[error]
