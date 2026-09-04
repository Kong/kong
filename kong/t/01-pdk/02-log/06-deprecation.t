use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
do "./t/Util.pm";

plan tests => repeat_each() * (blocks() * 4);

run_tests();

__DATA__

=== TEST 1: kong.log.deprecation() logs a deprecation message
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            require "kong.deprecation".init()
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            pdk.log.deprecation("example is deprecated")
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
example is deprecated
--- no_error_log
[error]
[crit]



=== TEST 2: kong.log.deprecation() logs a deprecation message with removal info
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            require "kong.deprecation".init()
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            pdk.log.deprecation("example is deprecated", { removal = "3.0.0" })
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
example is deprecated (scheduled for removal in 3.0.0)
--- no_error_log
[error]
[crit]



=== TEST 3: kong.log.deprecation() logs a deprecation message with deprecation info
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            require "kong.deprecation".init()
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            pdk.log.deprecation("example is deprecated", { after = "2.6.0" })
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
example is deprecated (deprecated after 2.6.0)
--- no_error_log
[error]
[crit]



=== TEST 4: kong.log.deprecation() logs a deprecation message with removal and deprecation info
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            require "kong.deprecation".init()
            local PDK = require "kong.pdk"
            local pdk = PDK.new()
            pdk.log.deprecation("example is deprecated", {
                after = "2.6.0",
                removal = "3.0.0",
            })
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
example is deprecated (deprecated after 2.6.0, scheduled for removal in 3.0.0)
--- no_error_log
[error]
[crit]
