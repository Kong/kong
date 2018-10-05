use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: response.get_source() returns "error" by default
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
        }

        header_filter_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            ngx.header["X-Source"] = pdk.response.get_source()
        }
    }
--- request
GET /t
--- response_headers
X-Source: error
--- no_error_log
[error]



=== TEST 2: response.get_source() returns "service" when the service has answered
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
          ngx.ctx.KONG_PROXIED = true
        }

        header_filter_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            ngx.header["X-Source"] = pdk.response.get_source()
        }
    }
--- request
GET /t
--- response_headers
X-Source: service
--- no_error_log
[error]



=== TEST 3: response.get_source() returns "exit" when kong.response.exit was previously used
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
          local PDK = require "kong.pdk"
          local pdk = PDK.new({ enabled_headers = {} })
          pdk.response.exit(200, "ok")
        }

        header_filter_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            ngx.header["X-Source"] = pdk.response.get_source()
        }
    }
--- request
GET /t
--- response_headers
X-Source: exit
--- no_error_log
[error]
