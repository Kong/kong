use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
do "./t/Util.pm";

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: client.set_authenticated_consumer_group() sets the consumer group
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.client.set_authenticated_consumer_group(setmetatable({},{
                __tostring = function() return "this consumer group" end,
            }))


            ngx.say("consumer_group: ", tostring(pdk.client.get_consumer_group()))
        }
    }
--- request
GET /t
--- response_body
consumer_group: this consumer group
--- no_error_log
[error]



=== TEST 2: client.set_authenticated_consumer_group() only accepts table as credential
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.client.set_authenticated_consumer_group, "not a table")

            ngx.say(tostring(err))
        }
    }
--- request
GET /t
--- response_body
consumer group must be a table or nil
--- no_error_log
[error]
