use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: client.set_consumer() sets the consumer
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.client.set_consumer(setmetatable({},{
                __tostring = function() return "this consumer" end,
            }),
            setmetatable({},{
                __tostring = function() return "this credential" end,
            }))


            ngx.say("consumer: ", tostring(pdk.client.get_consumer()), ", credential: ", tostring(pdk.client.get_credential()))
        }
    }
--- request
GET /t
--- response_body
consumer: this consumer, credential: this credential
--- no_error_log
[error]



=== TEST 2: client.set_consumer() allows setting nils
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.client.set_consumer(setmetatable({},{
                __tostring = function() return "this consumer" end,
            }),
            setmetatable({},{
                __tostring = function() return "this credential" end,
            }))

            -- now set the actual nils to overwrite the above values
            pdk.client.set_consumer(nil, nil)

            ngx.say("consumer: ", tostring(pdk.client.get_consumer()), ", credential: ", tostring(pdk.client.get_credential()))
        }
    }
--- request
GET /t
--- response_body
consumer: nil, credential: nil
--- no_error_log
[error]



=== TEST 3: client.set_consumer() only accepts table as consumer
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.client.set_consumer, "not_a_proper_consumer")

            ngx.say(tostring(err))
        }
    }
--- request
GET /t
--- response_body
consumer must be a table or nil
--- no_error_log
[error]



=== TEST 4: client.set_consumer() only accepts table as credential
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.client.set_consumer, nil, "not_a_proper_credential")

            ngx.say(tostring(err))
        }
    }
--- request
GET /t
--- response_body
credential must be a table or nil
--- no_error_log
[error]
