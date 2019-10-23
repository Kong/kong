use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: client.load_consumer() loads a consumer by id.
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            _G.kong = {
              ctx = {
                core = {
                  phase = 0x00000020,
                },
              },
              db = {
                consumers = {
                  select = function(self, query)
                    return { username = "bob" }, nil
                  end,
                },
              },
            }

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local consumer, err = pdk.client.load_consumer("5a61a36e-6133-4be7-b8be-6431d6e98019")
            ngx.say("consumer: " .. consumer.username)
        }
    }
--- request
GET /t
--- response_body
consumer: bob
--- no_error_log
[error]



=== TEST 2: client.load_consumer() loads a consumer by username
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            _G.kong = {
              ctx = {
                core = {
                  phase = 0x00000020,
                },
              },
              db = {
                consumers = {
                  select = function()
                    return
                  end,
                  select_by_username = function(self, query)
                    return { username = "bob" }, nil
                  end,
                },
              },
            }

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local consumer, err = pdk.client.load_consumer("bob", true)
            ngx.say("consumer: " .. consumer.username)
        }
    }
--- request
GET /t
--- response_body
consumer: bob
--- no_error_log
[error]



=== TEST 3: client.load_consumer() returns an error
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local consumer, err = pcall(pdk.client.load_consumer)
            ngx.say(tostring(err))
        }
    }
--- request
GET /t
--- response_body
consumer_id must be a string
--- no_error_log
[error]



=== TEST 4: client.load_consumer() errors for a non-uuid ID based search
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local consumer, err = pcall(pdk.client.load_consumer, "bob", false)
            --local consumer, err = pcall(pdk.client.load_consumer)
            ngx.say(tostring(err))
        }
    }
--- request
GET /t
--- response_body
cannot load a consumer with an id that is not a uuid
--- no_error_log
[error]

