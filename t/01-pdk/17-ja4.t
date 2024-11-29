use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
do "./t/Util.pm";

$ENV{TEST_NGINX_CERT_DIR} ||= File::Spec->catdir(server_root(), '..', 'certs');
$ENV{TEST_NGINX_NXSOCK}   ||= html_dir();

plan tests => repeat_each() * (blocks() * 2);

run_tests();

__DATA__

=== TEST 1: should work in these phases
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock ssl;
        ssl_certificate $ENV{TEST_NGINX_CERT_DIR}/test.crt;
        ssl_certificate_key $ENV{TEST_NGINX_CERT_DIR}/test.key;


        ssl_client_hello_by_lua_block {
            local ja4 = require "kong.pdk.private.ja4"
            local ret = ja4.compute_client_ja4()
            assert(ret == true, "unexpected value: " .. tostring(ret))
            ngx.ctx.connection = ngx.ctx
            ret = ja4.get_computed_client_ja4()
            assert(ret ~= '', "unexpected value: " .. tostring(ret))
        }

        ssl_certificate_by_lua_block {
            local ja4 = require "kong.pdk.private.ja4"
            local ret = ja4.get_computed_client_ja4()
            assert(ret ~= '', "unexpected value: " .. tostring(ret))
        }


        location / {
            set \$upstream_uri '/t';
            set \$upstream_scheme 'https';

            rewrite_by_lua_block {
                local ja4 = require "kong.pdk.private.ja4"
                local ret = ja4.get_computed_client_ja4()
                assert(ret ~= '', "unexpected value: " .. tostring(ret))
            }

            access_by_lua_block {
                local ja4 = require "kong.pdk.private.ja4"
                local ret = ja4.get_computed_client_ja4()
                assert(ret ~= '', "unexpected value: " .. tostring(ret))
            }

            header_filter_by_lua_block {
                local ja4 = require "kong.pdk.private.ja4"
                local ret = ja4.get_computed_client_ja4()
                assert(ret ~= '', "unexpected value: " .. tostring(ret))
            }

            body_filter_by_lua_block {
                local ja4 = require "kong.pdk.private.ja4"
                local ret = ja4.get_computed_client_ja4()
                assert(ret ~= '', "unexpected value: " .. tostring(ret))
            }

            log_by_lua_block {
                local ja4 = require "kong.pdk.private.ja4"
                local ret = ja4.get_computed_client_ja4()
                assert(ret ~= '', "unexpected value: " .. tostring(ret))
            }

            return 200;
        }
    }
}
--- config
    location /t {
        proxy_pass https://unix:$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- no_error_log
[error]
