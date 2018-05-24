use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: service.set_upstream() errors if not a string
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local pok, err = pcall(sdk.service.set_upstream, 127001)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
host must be a string
--- no_error_log
[error]



=== TEST 2: service.set_upstream() sets ngx.ctx.balancer_address.host
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

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.ctx.balancer_address = {
                host = "foo.xyz"
            }

            local ok = sdk.service.set_upstream("my_upstream")

            ngx.say(tostring(ok))
            ngx.say("host: ", ngx.ctx.balancer_address.host)
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

            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            ngx.ctx.balancer_address = {
                host = "foo.xyz"
            }

            local ok, err = sdk.service.set_upstream("not_an_upstream")

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
