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

=== TEST 1: request.get_scheme() returns http for plain text requests
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("scheme: ", pdk.request.get_scheme())
        }
    }
--- request
GET /t
--- response_body
scheme: http
--- no_error_log
[error]



=== TEST 2: request.get_scheme() returns https for TLS requests
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock ssl;
        ssl_certificate $ENV{TEST_NGINX_CERT_DIR}/test.crt;
        ssl_certificate_key $ENV{TEST_NGINX_CERT_DIR}/test.key;

        location / {
            content_by_lua_block {
            }

            access_by_lua_block {
                local PDK = require "kong.pdk"
                local pdk = PDK.new()

                ngx.say("scheme: ", pdk.request.get_scheme())
            }
        }
    }
}
--- config
    location = /t {
        proxy_ssl_verify off;
        proxy_pass https://unix:$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
scheme: https
--- no_error_log
[error]



=== TEST 3: request.get_scheme() is normalized
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("scheme: ", pdk.request.get_scheme())
        }
    }
--- request
GET HTTP://KONG/t
--- response_body
scheme: http
--- no_error_log
[error]
