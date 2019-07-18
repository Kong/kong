use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: service.set_tls_cert_key() errors if cert is not cdata
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.set_tls_cert_key, "foo", "bar")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
chain must be a parsed cdata object
--- no_error_log
[error]



=== TEST 2: service.set_tls_cert_key() errors if key is not cdata
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require("kong.pdk")
            local ffi = require("ffi")
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.set_tls_cert_key, ffi.new("void *"), "bar")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
key must be a parsed cdata object
--- no_error_log
[error]



=== TEST 3: service.set_tls_cert_key() works with valid cert and key
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require("kong.pdk")
            local ssl = require("ngx.ssl")
            local pdk = PDK.new()

            local f = assert(io.open("t/certs/test.crt"))
            local cert_data = f:read("*a")
            f:close()

            local chain = assert(ssl.parse_pem_cert(cert_data))

            f = assert(io.open("t/certs/test.key"))
            local key_data = f:read("*a")
            f:close()
            local key = assert(ssl.parse_pem_priv_key(key_data))


            local ok, err = pdk.service.set_tls_cert_key(chain, key)
            ngx.say(ok, ", ", err)
        }
    }
--- request
GET /t
--- response_body
true, nil
--- no_error_log
[error]
