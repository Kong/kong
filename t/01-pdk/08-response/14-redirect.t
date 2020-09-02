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

=== TEST 1: response.redirect() redirect uri
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.response.redirect("http://github.com")
        }
    }
--- request
GET /t
--- error_code: 301
--- response_body_like chomp
301 Moved Permanently
--- no_error_log
[error]



=== TEST 2: response.redirect() errors if uri is invalid
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
        }

         header_filter_by_lua_block {
            ngx.header.content_length = nil

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local ok, err = pcall(pdk.response.redirect, "invalid_url")
            if not ok then
                ngx.ctx.err = err
            end
        }

        body_filter_by_lua_block {
            ngx.arg[1] = ngx.ctx.err
            ngx.arg[2] = true
        }
    }
--- request
GET /t
--- response_body chop
cannot parse 'invalid_url'
--- no_error_log
[error]
