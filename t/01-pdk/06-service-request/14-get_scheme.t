use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use File::Spec;
use t::Util;

$ENV{TEST_NGINX_CERT_DIR} ||= File::Spec->catdir(server_root(), '..', 'certs');
$ENV{TEST_NGINX_NXSOCK}   ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: service.request.get_scheme() returns http
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        set $upstream_scheme 'http';

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("scheme: ", pdk.service.request.get_scheme())
        }
    }
--- request
GET /t
--- response_body
scheme: http
--- no_error_log
[error]



=== TEST 2: service.request.get_scheme() returns https
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        set $upstream_scheme 'https';

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("scheme: ", pdk.service.request.get_scheme())
        }
    }
--- request
GET /t
--- response_body
scheme: https
--- no_error_log
[error]
