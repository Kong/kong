use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_CERT_DIR} ||= File::Spec->catdir(server_root(), '..', 'certs');
$ENV{TEST_NGINX_NXSOCK}   ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_forwarded_path() considers X-Forwarded-Path when trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new({ trusted_ips = { "0.0.0.0/0", "::/0" } })

            ngx.say("path: ", pdk.request.get_forwarded_path())
            ngx.say("type: ", type(pdk.request.get_forwarded_path()))
        }
    }
--- request
GET /t/request-path
--- more_headers
X-Forwarded-Path: /trusted
--- response_body
path: /trusted
type: string
--- no_error_log
[error]



=== TEST 2: request.get_forwarded_path() doesn't considers X-Forwarded-Path when not trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("path: ", pdk.request.get_forwarded_path())
        }
    }
--- request
GET /t/request-path
--- more_headers
X-Forwarded-Path: /not-trusted
--- response_body
path: /t/request-path
--- no_error_log
[error]



=== TEST 3: request.get_forwarded_path() considers first X-Forwarded-Path if multiple when trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new({ trusted_ips = { "0.0.0.0/0", "::/0" } })

            ngx.say("path: ", pdk.request.get_forwarded_path())
        }
    }
--- request
GET /t
--- more_headers
X-Forwarded-Path: /first
X-Forwarded-Path: /second
--- response_body
path: /first
--- no_error_log
[error]



=== TEST 4: request.get_forwarded_path() doesn't considers any X-Forwarded-Path headers when not trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("path: ", pdk.request.get_forwarded_path())
        }
    }
--- request
GET /t/request-uri
--- more_headers
X-Forwarded-Path: /first
X-Forwarded-Path: /second
--- response_body
path: /t/request-uri
--- no_error_log
[error]



=== TEST 5: request.get_forwarded_path() removes query and fragment when not trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("path: ", pdk.request.get_forwarded_path())
        }
    }
--- request
GET /t/request-uri?query&field=value#here
--- more_headers
X-Forwarded-Path: /first
--- response_body
path: /t/request-uri
--- no_error_log
[error]



=== TEST 6: request.get_forwarded_path() does not remove query and fragment when trusted
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new({ trusted_ips = { "0.0.0.0/0", "::/0" } })

            ngx.say("path: ", pdk.request.get_forwarded_path())
        }
    }
--- request
GET /t/request-uri?query&field=value#here
--- more_headers
X-Forwarded-Path: /first?query&field=value#here
--- response_body
path: /first?query&field=value#here
--- no_error_log
[error]
