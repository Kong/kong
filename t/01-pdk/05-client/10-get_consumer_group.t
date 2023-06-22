use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
do "./t/Util.pm";

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: client.get_consumer_group() returns selected consumer group
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            ngx.ctx.authenticated_consumer_group = setmetatable({},{
                __tostring = function() return "this consumer group" end,
            })

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("consumer_group: ", tostring(pdk.client.get_consumer_group()))
        }
    }
--- request
GET /t
--- response_body
consumer_group: this consumer group
--- no_error_log
[error]
