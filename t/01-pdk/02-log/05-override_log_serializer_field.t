use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 3 + 1);

run_tests();

__DATA__

=== TEST 1: pdk.log.override_log_serializer_field() sets correct ctx field
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require("kong.pdk")
            local pdk = PDK.new()

            pdk.log.override_log_serializer_field("basic", "request.tls.client_verify", "SUCCESS")

            ngx.say(ngx.ctx.basic_serializer_overrides["request.tls.client_verify"])
        }
    }
--- request
GET /t
--- response_body
SUCCESS
--- no_error_log
[error]
[crit]



=== TEST 2: pdk.log.override_log_serializer_field() errors when incorrect serializer type is given
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require("kong.pdk")
            local pdk = PDK.new()

            pdk.log.override_log_serializer_field("bad", "request.tls.client_verify", "SUCCESS")

            ngx.say(ngx.ctx.basic_serializer_overrides["request.tls.client_verify"])
        }
    }
--- request
GET /t
--- error_code: 500
--- error_log
unsupported log serializer type, only "basic" is supported
--- no_error_log
[crit]



=== TEST 3: pdk.log.override_log_serializer_field() errors when value is not expected
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require("kong.pdk")
            local pdk = PDK.new()

            pdk.log.override_log_serializer_field("basic", "request.tls.client_verify", "success")

            ngx.say(ngx.ctx.basic_serializer_overrides["request.tls.client_verify"])
        }
    }
--- request
GET /t
--- error_code: 500
--- error_log
bad field value: only "SUCCESS", "FAILED:reason", and "NONE" are accepted
--- no_error_log
[crit]



=== TEST 4: pdk.log.override_log_serializer_field() errors when nil is given
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require("kong.pdk")
            local pdk = PDK.new()

            pdk.log.override_log_serializer_field("basic", "request.tls.client_verify", nil)

            ngx.say(ngx.ctx.basic_serializer_overrides["request.tls.client_verify"])
        }
    }
--- request
GET /t
--- error_code: 500
--- error_log
overriding value can not be nil
--- no_error_log
[crit]
