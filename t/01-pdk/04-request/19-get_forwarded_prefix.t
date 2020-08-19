use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_CERT_DIR} ||= File::Spec->catdir(server_root(), '..', 'certs');
$ENV{TEST_NGINX_NXSOCK}   ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_forwarded_prefix() considers X-Forwarded-Prefix when trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new({ trusted_ips = { "0.0.0.0/0", "::/0" } })
            ngx.say("prefix: ", pdk.request.get_forwarded_prefix())
            ngx.say("type: ", type(pdk.request.get_forwarded_prefix()))
        }
    }
--- request
GET /t/request-path
--- more_headers
X-Forwarded-Prefix: /trusted
--- response_body
prefix: /trusted
type: string
--- no_error_log
[error]



=== TEST 2: request.get_forwarded_prefix() doesn't consider X-Forwarded-Prefix when not trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            ngx.say("prefix: ", pdk.request.get_forwarded_prefix())
        }
    }
--- request
GET /t/request-path
--- more_headers
X-Forwarded-Prefix: /trusted
--- response_body
prefix: nil
--- no_error_log
[error]



=== TEST 3: request.get_forwarded_prefix() considers first X-Forwarded-Prefix if multiple when trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new({ trusted_ips = { "0.0.0.0/0", "::/0" } })
            ngx.say("prefix: ", pdk.request.get_forwarded_prefix())
        }
    }
--- request
GET /t
--- more_headers
X-Forwarded-Prefix: /first
X-Forwarded-Prefix: /second
--- response_body
prefix: /first
--- no_error_log
[error]



=== TEST 4: request.get_forwarded_prefix() does not remove query and fragment when trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new({ trusted_ips = { "0.0.0.0/0", "::/0" } })
            ngx.say("prefix: ", pdk.request.get_forwarded_prefix())
        }
    }
--- request
GET /t/request-uri?query&field=value#here
--- more_headers
X-Forwarded-Prefix: /first?query&field=value#here
--- response_body
prefix: /first?query&field=value#here
--- no_error_log
[error]
