use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: node.get_id() returns node identifier
--- http_config eval
qq{
    $t::Util::HttpConfig

    lua_shared_dict kong 24k;
}
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            math.randomseed(ngx.time())

            ngx.say(pdk.node.get_id())
        }
    }
--- request
GET /t
--- response_body_like
[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}
--- no_error_log
[error]
