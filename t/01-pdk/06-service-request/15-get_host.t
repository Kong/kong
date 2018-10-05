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

=== TEST 1: service.request.get_host() returns upstream host
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            ngx.ctx.balancer_data = {
                host = "kong"
            }

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("host: ", pdk.service.request.get_host())
        }
    }
--- request
GET /t
--- response_body
host: kong
--- no_error_log
[error]
