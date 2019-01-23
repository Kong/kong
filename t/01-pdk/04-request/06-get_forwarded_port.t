use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_CERT_DIR} ||= File::Spec->catdir(server_root(), '..', 'certs');
$ENV{TEST_NGINX_NXSOCK}   ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_forwarded_port() considers X-Forwarded-Port when trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new({ trusted_ips = { "0.0.0.0/0", "::/0" } })

            ngx.say("port: ", pdk.request.get_forwarded_port())
            ngx.say("type: ", type(pdk.request.get_forwarded_port()))
        }
    }
--- request
GET /t
--- more_headers
X-Forwarded-Port: 1234
--- response_body
port: 1234
type: number
--- no_error_log
[error]



=== TEST 2: request.get_forwarded_port() doesn't considers X-Forwarded-Port when not trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("port: ", pdk.request.get_forwarded_port())
        }
    }
--- request
GET /t
--- more_headers
X-Forwarded-Port: 1234
--- response_body_unlike
port: 1234
--- response_body_like
port: \d+
--- no_error_log
[error]



=== TEST 3: request.get_forwarded_port() considers first X-Forwarded-Port if multiple when trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new({ trusted_ips = { "0.0.0.0/0", "::/0" } })

            ngx.say("port: ", pdk.request.get_forwarded_port())
        }
    }
--- request
GET /t
--- more_headers
X-Forwarded-Port: 1234
X-Forwarded-Port: 5678
--- response_body
port: 1234
--- no_error_log
[error]



=== TEST 4: request.get_forwarded_port() doesn't considers any X-Forwarded-Port headers when not trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("port: ", pdk.request.get_forwarded_port())
        }
    }
--- request
GET /t
--- more_headers
X-Forwarded-Port: 1234
X-Forwarded-Port: 5678
--- response_body_unlike
port: (1234|5678)
--- response_body_like
port: \d+
--- no_error_log
[error]



=== TEST 5: request.get_forwarded_port() falls back to port used in last hop (http)
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new({ trusted_ips = { "0.0.0.0/0", "::/0" } })

            ngx.say("port: ", pdk.request.get_forwarded_port())
        }
    }
--- request
GET /t
--- response_body_like
port: \d+
--- no_error_log
[error]



=== TEST 6: request.get_forwarded_port() falls back to port used in last hop (https)
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
                local pdk = PDK.new({ trusted_ips = { "0.0.0.0/0", "::/0" } })

                ngx.say("port: ", pdk.request.get_forwarded_port())
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
port: nil
--- no_error_log
[error]
