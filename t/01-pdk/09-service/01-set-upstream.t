use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: service.set_upstream() errors if not a string
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.set_upstream, 127001)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
host must be a string
--- no_error_log
[error]



=== TEST 2: service.set_upstream() sets ngx.ctx.balancer_data.host
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {

        set $upstream_host '';

        content_by_lua_block {

            -- mock kong.runloop.balancer
            package.loaded["kong.runloop.balancer"] = {
                get_upstream_by_name = function(name)
                    if name == "my_upstream" then
                        return {}
                    end
                end
            }

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.ctx.balancer_data = {
                host = "foo.xyz"
            }

            local ok = pdk.service.set_upstream("my_upstream")

            ngx.say(tostring(ok))
            ngx.say("host: ", ngx.ctx.balancer_data.host)
        }
    }
--- request
GET /t
--- response_body
true
host: my_upstream
--- no_error_log
[error]



=== TEST 3: service.set_upstream() fails when given an invalid upstream
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {

        set $upstream_host '';

        content_by_lua_block {

            -- mock kong.runloop.balancer
            package.loaded["kong.runloop.balancer"] = {
                get_upstream_by_name = function(name)
                    if name == "my_upstream" then
                        return {}
                    end
                end
            }

            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.ctx.balancer_data = {
                host = "foo.xyz"
            }

            local ok, err = pdk.service.set_upstream("not_an_upstream")

            ngx.say(tostring(ok))
            ngx.say("err: ", err)
        }
    }
--- request
GET /t
--- response_body
nil
err: could not find an Upstream named 'not_an_upstream'
--- no_error_log
[error]
