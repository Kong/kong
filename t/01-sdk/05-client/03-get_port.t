use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use File::Spec;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();
$ENV{TEST_NGINX_CERT_DIR} ||= File::Spec->catdir(server_root(), '..', 'certs');

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: client.get_port() returns client port
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()
            --sdk.init(nil, "ip")

            ngx.say("port: ", sdk.client.get_port())
        }
    }
--- request
GET /t
--- response_body_like chomp
port: \d+
--- no_error_log
[error]



=== TEST 2: client.get_port() returns a number
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()
            --sdk.init(nil, "ip")

            ngx.say("port type: ", type(sdk.client.get_port()))
        }
    }
--- request
GET /t
--- response_body
port type: number
--- no_error_log
[error]
