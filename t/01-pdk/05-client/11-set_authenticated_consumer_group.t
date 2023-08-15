use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
do "./t/Util.pm";

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: client.set_authenticated_consumer_groups() sets the consumer groups
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.client.set_authenticated_consumer_groups(setmetatable({},{
                __tostring = function() return "multiple consumer groups" end,
            }))


            ngx.say("consumer_groups: ", tostring(pdk.client.get_consumer_groups()))
        }
    }
--- request
GET /t
--- response_body
consumer_groups: multiple consumer groups
--- no_error_log
[error]


=== TEST 2: client.set_authenticated_consumer_group() sets the consumer group
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.client.set_authenticated_consumer_group(setmetatable({},{
                __tostring = function() return "single consumer group" end,
            }))


            ngx.say("consumer_groups: ", tostring(pdk.client.get_consumer_group()))
        }
    }
--- request
GET /t
--- response_body
consumer_groups: single consumer group
--- no_error_log
[error]

=== TEST 3: client.set_authenticated_consumer_groups() only accepts table as credential
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.client.set_authenticated_consumer_groups, "not a table")

            ngx.say(tostring(err))
        }
    }
--- request
GET /t
--- response_body
consumer group must be a table or nil
--- no_error_log
[error]
