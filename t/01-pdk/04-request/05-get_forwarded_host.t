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

=== TEST 1: request.get_forwarded_host() returns host using host header from last hop when not trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("host: ", pdk.request.get_forwarded_host())
        }
    }
--- request
GET /t
--- more_headers
X-Forwarded-Host: test
--- response_body
host: localhost
--- no_error_log
[error]



=== TEST 2: request.get_forwarded_host() returns host using host header with tls from last hop when not trusted
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

                ngx.say("host: ", pdk.request.get_forwarded_host())
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
--- more_headers
X-Forwarded-Host: test
--- response_body
host: localhost
--- no_error_log
[error]



=== TEST 3: request.get_forwarded_host() returns host using server name from last hop when not trusted
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        server_name kong;
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location / {
            content_by_lua_block {
            }

            access_by_lua_block {
                local PDK = require "kong.pdk"
                local pdk = PDK.new()

                ngx.say("host: ", pdk.request.get_forwarded_host())
            }
        }
    }
}
--- config
    location /t {
        proxy_set_header Host "";
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- more_headers
X-Forwarded-Host: test
--- response_body
host: kong
--- no_error_log
[error]



=== TEST 4: request.get_forwarded_host() returns host using request line from last hop when not trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("host: ", pdk.request.get_forwarded_host())
        }
    }
--- request
GET http://test/t
--- more_headers
X-Forwarded-Host: kong
--- response_body
host: test
--- no_error_log
[error]



=== TEST 5: request.get_forwarded_host() returns host using explicit host header from last hop when not trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("host: ", pdk.request.get_forwarded_host())
        }
    }
--- request
GET /t
--- more_headers
Host: kong
X-Forwarded-Host: test
--- response_body
host: kong
--- no_error_log
[error]



=== TEST 6: request.get_forwarded_host() request line overrides host header from last hop when not trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("host: ", pdk.request.get_forwarded_host())
        }
    }
--- request
GET http://test/t
--- more_headers
Host: kong
X-Forwarded-Host: test
--- response_body
host: test
--- no_error_log
[error]



=== TEST 7: request.get_host() request line is normalized and taken from last hop when not trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("host: ", pdk.request.get_forwarded_host())
        }
    }
--- request
GET http://TEST/t
--- more_headers
Host: kong
X-Forwarded-Host: not-trusted
--- response_body
host: test
--- no_error_log
[error]



=== TEST 8: request.get_host() explicit host header is normalized and taken from last hop when not trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("host: ", pdk.request.get_forwarded_host())
        }
    }
--- request
GET /t
--- more_headers
Host: K0nG
X-Forwarded-Host: not-trusted
--- response_body
host: k0ng
--- no_error_log
[error]



=== TEST 9: request.get_host() server name is normalized and used when not trusted
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        server_name k0ng;
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location / {
            content_by_lua_block {
            }

            access_by_lua_block {
                local PDK = require "kong.pdk"
                local pdk = PDK.new()

                ngx.say("host: ", pdk.request.get_host())
            }
        }
    }
}
--- config
    location /t {
        proxy_set_header Host "";
        proxy_pass http://unix:$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- more_headers
X-Forwarded-Host: not-trusted
--- response_body
host: k0ng
--- no_error_log
[error]



=== TEST 10: request.get_forwarded_host() returns host from forwarded host header when trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new({
                trusted_ips = { "0.0.0.0/0", "::/0" }
            })

            ngx.say("host: ", pdk.request.get_forwarded_host())
        }
    }
--- request
GET /t
--- more_headers
X-Forwarded-Host: test
--- response_body
host: test
--- no_error_log
[error]



=== TEST 11: request.get_forwarded_host() returns host from forwarded host header with tls when trusted
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
                local pdk = PDK.new({
                    trusted_ips = { "0.0.0.0/0", "::/0" }
                })

                ngx.say("host: ", pdk.request.get_forwarded_host())
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
--- more_headers
X-Forwarded-Host: test
--- response_body
host: test
--- no_error_log
[error]



=== TEST 12: request.get_forwarded_host() forwarded host overrides request line and host header when trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new({
                trusted_ips = { "0.0.0.0/0", "::/0" }
            })

            ngx.say("host: ", pdk.request.get_forwarded_host())
        }
    }
--- request
GET http://demo/t
--- more_headers
Host: kong
X-Forwarded-Host: test
--- response_body
host: test
--- no_error_log
[error]



=== TEST 13: request.get_host() forwarded host header is normalized
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new({
                trusted_ips = { "0.0.0.0/0", "::/0" }
            })

            ngx.say("host: ", pdk.request.get_forwarded_host())
        }
    }
--- request
GET /t
--- more_headers
Host: test
X-Forwarded-Host: K0nG
--- response_body
host: k0ng
--- no_error_log
[error]
